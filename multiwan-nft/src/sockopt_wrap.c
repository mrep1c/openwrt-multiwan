// SPDX-License-Identifier: GPL-2.0
/* Copyright (C) 2020 Aaron Goodman <aaronjg@alumni.stanford.edu>. */

/* Bind dynamically linked commands to DEVICE/SRCIP/FWMARK and optional FAMILY. */
#define _GNU_SOURCE
#include <arpa/inet.h>
#include <dlfcn.h>
#include <errno.h>
#include <linux/if_packet.h>
#include <net/if.h>
#include <netdb.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>

static int (*next_socket)(int, int, int);
static int (*next_setsockopt)(int, int, int, const void *, socklen_t);
static int (*next_bind)(int, const struct sockaddr *, socklen_t);
static int (*next_close)(int);
static int (*next_getaddrinfo)(const char *, const char *, const struct addrinfo *,
                              struct addrinfo **);
static int (*next_connect)(int, const struct sockaddr *, socklen_t);
static ssize_t (*next_send)(int, const void *, size_t, int);
static ssize_t (*next_sendto)(int, const void *, size_t, int,
                            const struct sockaddr *, socklen_t);
static ssize_t (*next_sendmsg)(int, const struct msghdr *, int);
/* The GNU extension uses different flag signedness in glibc and musl. */
#ifdef __GLIBC__
typedef int sendmmsg_flags_t;
#else
typedef unsigned int sendmmsg_flags_t;
#endif
static int (*next_sendmmsg)(int, struct mmsghdr *, unsigned int, sendmmsg_flags_t);

static char device[IFNAMSIZ];
static uint32_t mark;
static int has_mark, family, source_family, config_error;
static struct sockaddr_storage source;
static socklen_t source_size;

static void __attribute__((constructor)) initialize(void)
{
    const char *value;
    char *end;
    unsigned long long parsed;

#define RESOLVE(name) do { \
    const char *error; \
    dlerror(); \
    next_##name = dlsym(RTLD_NEXT, #name); \
    error = dlerror(); \
    if (error) { \
        fprintf(stderr, "multiwan socket wrapper: %s\n", error); \
        _exit(127); \
    } \
} while (0)
    RESOLVE(socket);
    RESOLVE(setsockopt);
    RESOLVE(bind);
    RESOLVE(close);
    RESOLVE(getaddrinfo);
    RESOLVE(connect);
    RESOLVE(send);
    RESOLVE(sendto);
    RESOLVE(sendmsg);
    RESOLVE(sendmmsg);
#undef RESOLVE

    value = getenv("DEVICE");
    if (value && *value) {
        if (strlen(value) >= sizeof(device))
            config_error = ENAMETOOLONG;
        else
            strcpy(device, value);
    }
    value = getenv("FWMARK");
    if (value && *value) {
        errno = 0;
        parsed = strtoull(value, &end, 0);
        if (errno || *end || value[0] == '-' || parsed > UINT32_MAX)
            config_error = EINVAL;
        else {
            has_mark = 1;
            mark = (uint32_t)parsed;
        }
    }
    value = getenv("FAMILY");
    if (value && *value) {
        if (!strcmp(value, "ipv4"))
            family = AF_INET;
        else if (!strcmp(value, "ipv6"))
            family = AF_INET6;
        else
            config_error = EINVAL;
    }
    value = getenv("SRCIP");
    if (value && *value) {
        struct sockaddr_in *v4 = (struct sockaddr_in *)&source;
        struct sockaddr_in6 *v6 = (struct sockaddr_in6 *)&source;
        if (inet_pton(AF_INET, value, &v4->sin_addr) == 1) {
            source_family = source.ss_family = AF_INET;
            source_size = sizeof(*v4);
        } else if (inet_pton(AF_INET6, value, &v6->sin6_addr) == 1) {
            source_family = source.ss_family = AF_INET6;
            source_size = sizeof(*v6);
        } else
            config_error = EINVAL;
        if (family && source_family && family != source_family)
            config_error = EINVAL;
    }
}

int getaddrinfo(const char *node, const char *service, const struct addrinfo *hints,
                struct addrinfo **result)
{
    struct addrinfo selected = {0};
    int domain = family ? family : source_family;

    if (config_error) {
        errno = config_error;
        return EAI_SYSTEM;
    }
    if (!domain)
        return next_getaddrinfo(node, service, hints, result);
    /* Nping canonicalizes both families while enumerating interface addresses. */
    if (hints && hints->ai_family != AF_UNSPEC && (hints->ai_flags & AI_NUMERICHOST))
        return next_getaddrinfo(node, service, hints, result);
    if (hints)
        selected = *hints;
    if (selected.ai_family != AF_UNSPEC && selected.ai_family != domain)
        return EAI_FAMILY;
    selected.ai_family = domain;
    /* A mapped IPv4 address would bypass an IPv6-only family selection. */
    selected.ai_flags &= ~(AI_V4MAPPED | AI_ALL);
    return next_getaddrinfo(node, service, &selected, result);
}

static int source_matches(const struct sockaddr_storage *address)
{
    if (address->ss_family == AF_INET)
        return ((const struct sockaddr_in *)address)->sin_addr.s_addr ==
               ((const struct sockaddr_in *)&source)->sin_addr.s_addr;
    return !memcmp(&((const struct sockaddr_in6 *)address)->sin6_addr,
                   &((const struct sockaddr_in6 *)&source)->sin6_addr,
                   sizeof(struct in6_addr));
}

static int check_family(int domain)
{
    if ((domain == AF_INET || domain == AF_INET6) &&
        ((family && family != domain) || (source_family && source_family != domain))) {
        errno = EAFNOSUPPORT;
        return -1;
    }
    return 0;
}

static int bind_source(int fd)
{
    struct sockaddr_storage address;
    struct sockaddr_storage selected = source;
    socklen_t size = sizeof(address);
    int saved;

    if (!source_family && !family)
        return 0;
    if (getsockname(fd, (struct sockaddr *)&address, &size))
        return -1;
    if (address.ss_family != AF_INET && address.ss_family != AF_INET6)
        return 0;
    if (check_family(address.ss_family))
        return -1;
    if (!source_family)
        return 0;
    if (source_matches(&address))
        return 0;
    if (source_family == AF_INET6 && device[0])
        ((struct sockaddr_in6 *)&selected)->sin6_scope_id = if_nametoindex(device);
    if (!next_bind(fd, (struct sockaddr *)&selected, source_size))
        return 0;
    saved = errno;
    /* Another thread can bind the same underlying socket through a dup fd. */
    if ((saved == EINVAL || saved == EADDRINUSE) &&
        !getsockname(fd, (struct sockaddr *)&address, &size) && source_matches(&address))
        return 0;
    errno = saved;
    return -1;
}

int connect(int fd, const struct sockaddr *address, socklen_t size)
{
    if (bind_source(fd))
        return -1;
    return next_connect(fd, address, size);
}

ssize_t send(int fd, const void *buffer, size_t size, int flags)
{
    if (bind_source(fd))
        return -1;
    return next_send(fd, buffer, size, flags);
}

ssize_t sendto(int fd, const void *buffer, size_t size, int flags,
               const struct sockaddr *address, socklen_t length)
{
    if (bind_source(fd))
        return -1;
    return next_sendto(fd, buffer, size, flags, address, length);
}

ssize_t sendmsg(int fd, const struct msghdr *message, int flags)
{
    if (bind_source(fd))
        return -1;
    return next_sendmsg(fd, message, flags);
}

int sendmmsg(int fd, struct mmsghdr *messages, unsigned int count, sendmmsg_flags_t flags)
{
    if (bind_source(fd))
        return -1;
    return next_sendmmsg(fd, messages, count, flags);
}

int bind(int fd, const struct sockaddr *address, socklen_t size)
{
    struct sockaddr_storage selected;

    if (!address || size < sizeof(address->sa_family) || size > sizeof(selected))
        return next_bind(fd, address, size);
    if (check_family(address->sa_family))
        return -1;
    if (source_family && address->sa_family == source_family && size >= source_size) {
        memcpy(&selected, address, source_size);
        if (source_family == AF_INET)
            ((struct sockaddr_in *)&selected)->sin_addr =
                ((struct sockaddr_in *)&source)->sin_addr;
        else {
            ((struct sockaddr_in6 *)&selected)->sin6_addr =
                ((struct sockaddr_in6 *)&source)->sin6_addr;
            if (device[0])
                ((struct sockaddr_in6 *)&selected)->sin6_scope_id = if_nametoindex(device);
        }
        return next_bind(fd, (struct sockaddr *)&selected, source_size);
    }
    if (device[0] && address->sa_family == AF_PACKET && size >= sizeof(struct sockaddr_ll)) {
        memcpy(&selected, address, sizeof(struct sockaddr_ll));
        ((struct sockaddr_ll *)&selected)->sll_ifindex = if_nametoindex(device);
        if (!((struct sockaddr_ll *)&selected)->sll_ifindex) {
            errno = ENODEV;
            return -1;
        }
        return next_bind(fd, (struct sockaddr *)&selected, sizeof(struct sockaddr_ll));
    }
    return next_bind(fd, address, size);
}

int setsockopt(int fd, int level, int option, const void *value, socklen_t size)
{
    if (level == SOL_SOCKET && option == SO_MARK && has_mark)
        return next_setsockopt(fd, level, option, &mark, sizeof(mark));
    if (level == SOL_SOCKET && option == SO_BINDTODEVICE && device[0])
        return next_setsockopt(fd, level, option, device, strlen(device) + 1);
    return next_setsockopt(fd, level, option, value, size);
}

int socket(int domain, int type, int protocol)
{
    int fd, saved;
    struct sockaddr_ll packet = { .sll_family = AF_PACKET, .sll_protocol = protocol };

    if (domain != AF_INET && domain != AF_INET6 && domain != AF_PACKET)
        return next_socket(domain, type, protocol);
    if (config_error) {
        errno = config_error;
        return -1;
    }
    /* Interface ioctls need IPv4 datagram sockets even during IPv6 probes. */
    if ((type & ~(SOCK_CLOEXEC | SOCK_NONBLOCK)) != SOCK_DGRAM && check_family(domain))
        return -1;
    fd = next_socket(domain, type, protocol);
    if (fd < 0)
        return fd;
    if (device[0]) {
        if (domain == AF_PACKET) {
            packet.sll_ifindex = if_nametoindex(device);
            if (!packet.sll_ifindex) {
                errno = ENODEV;
                goto failed;
            }
            if (next_bind(fd, (struct sockaddr *)&packet, sizeof(packet)))
                goto failed;
        } else if (next_setsockopt(fd, SOL_SOCKET, SO_BINDTODEVICE, device, strlen(device) + 1))
            goto failed;
    }
    if (has_mark && next_setsockopt(fd, SOL_SOCKET, SO_MARK, &mark, sizeof(mark)))
        goto failed;
    return fd;

failed:
    saved = errno;
    next_close(fd);
    errno = saved;
    return -1;
}
