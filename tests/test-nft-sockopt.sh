#!/bin/sh

set -eu
if [ "${1:-}" = --inside ]; then
    TEST_ROOT="$2"
    ip link set lo up
    for dev in wan0 wan1; do
        ip link add "$dev" type dummy
        ip link set "$dev" up
    done
    ip address add 192.0.2.2/24 dev wan0
    ip address add 198.51.100.2/24 dev wan1
    ip address add 198.51.100.3/24 dev wan1
    ip -6 address add 2001:db8:2::2/64 dev wan1 nodad
    ip -6 address add 2001:db8:2::3/64 dev wan1 nodad
    ip route add default dev wan0
    ip route add 203.0.113.1 dev wan1
    ip -6 route add 2001:db8:ffff::1 dev wan1
    ip neighbor add 203.0.113.1 lladdr 02:00:00:00:00:01 nud permanent dev wan1
    ip -6 neighbor add 2001:db8:ffff::1 lladdr 02:00:00:00:00:01 nud permanent dev wan1
    nft -f - <<'NFT'
table inet socket_test {
    chain output {
        type filter hook output priority filter;
        ip saddr 198.51.100.3 ip daddr 203.0.113.1 udp dport 45000 meta oifname "wan1" meta mark 0x80010000 counter comment "packet4"
        ip6 saddr 2001:db8:2::3 ip6 daddr 2001:db8:ffff::1 udp dport 45000 meta oifname "wan1" meta mark 0x80010000 counter comment "packet6"
    }
}
NFT
    export LD_PRELOAD="$TEST_ROOT/wrapper.so" DEVICE=wan1 FWMARK=0x80010000 FAMILY=ipv4 SRCIP=198.51.100.3
    "$TEST_ROOT/probe" resolve4
    FAMILY=ipv6 SRCIP=2001:db8:2::3 "$TEST_ROOT/probe" resolve6
    FAMILY= SRCIP=2001:db8:2::3 "$TEST_ROOT/probe" resolve6
    FAMILY= SRCIP= "$TEST_ROOT/probe" resolve_both
    "$TEST_ROOT/probe" inspect4
    "$TEST_ROOT/probe" packet4
    "$TEST_ROOT/probe" messages
    "$TEST_ROOT/probe" threads
    "$TEST_ROOT/probe" packet_socket
    FAMILY=ipv6 SRCIP=2001:db8:2::3 "$TEST_ROOT/probe" inspect6
    FAMILY=ipv6 SRCIP=2001:db8:2::3 "$TEST_ROOT/probe" packet6
    "$TEST_ROOT/probe" metadata6
    FAMILY=ipv6 SRCIP=2001:db8:2::3 "$TEST_ROOT/probe" metadata4
    SRCIP= "$TEST_ROOT/probe" metadata6
    FWMARK=0 "$TEST_ROOT/probe" zero_mark
    DEVICE=missing0 "$TEST_ROOT/probe" error ENODEV
    DEVICE=interface-name-is-too-long "$TEST_ROOT/probe" error ENAMETOOLONG
    FWMARK=0x100000000 "$TEST_ROOT/probe" error EINVAL
    FWMARK=-1 "$TEST_ROOT/probe" error EINVAL
    FWMARK=garbage "$TEST_ROOT/probe" error EINVAL
    SRCIP=garbage "$TEST_ROOT/probe" error EINVAL
    FAMILY=garbage "$TEST_ROOT/probe" error EINVAL
    FAMILY=ipv6 "$TEST_ROOT/probe" error EINVAL
    DEVICE= FWMARK= SRCIP= FAMILY= "$TEST_ROOT/probe" optional
    LD_PRELOAD= "$TEST_ROOT/probe" tcp_server "$TEST_ROOT/tcp-ready" &
    server_pid=$!
    for attempt in $(seq 1 100); do
        [ ! -f "$TEST_ROOT/tcp-ready" ] || break
        sleep 0.02
    done
    [ -f "$TEST_ROOT/tcp-ready" ]
    DEVICE=lo SRCIP=127.0.0.2 "$TEST_ROOT/probe" tcp_client
    wait "$server_pid"
    unset LD_PRELOAD
    nft list chain inet socket_test output | grep 'comment "packet4"' | grep -q 'counter packets 1 '
    nft list chain inet socket_test output | grep 'comment "packet6"' | grep -q 'counter packets 1 '
    printf 'Socket binding tests passed: source/device/mark egress, IPv4/IPv6, explicit/failed binds, high/duplicate descriptors, threads, invalid input.\n'
    exit 0
fi

# The namespace child may not traverse the runner's private home directory.
TEST_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="${TEST_DIR%/tests}"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/multiwan-nft-sockopt.XXXXXX")" || exit 1
trap 'rm -rf "$TEST_ROOT"' EXIT HUP INT TERM
"${CC:-cc}" -std=gnu11 -O2 -Wall -Wextra -Werror -fPIC -shared \
    "$REPO_ROOT/multiwan-nft/src/sockopt_wrap.c" -ldl -o "$TEST_ROOT/wrapper.so"
cat > "$TEST_ROOT/probe.c" <<'C'
#define _GNU_SOURCE
#include <arpa/inet.h>
#include <assert.h>
#include <errno.h>
#include <fcntl.h>
#include <linux/if_ether.h>
#include <linux/if_packet.h>
#include <net/if.h>
#include <netdb.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/ioctl.h>
#include <unistd.h>

static const struct sockaddr_in destination4 = {
    .sin_family = AF_INET, .sin_port = __constant_htons(45000),
    .sin_addr = { .s_addr = __constant_htonl(0xcb007101) }
};

static void options(int fd, uint32_t expected_mark)
{
    uint32_t actual = 0;
    char name[IFNAMSIZ] = {0};
    socklen_t length = sizeof(actual);
    assert(getsockopt(fd, SOL_SOCKET, SO_MARK, &actual, &length) == 0);
    assert(actual == expected_mark);
    length = sizeof(name);
    assert(getsockopt(fd, SOL_SOCKET, SO_BINDTODEVICE, name, &length) == 0);
    assert(!strcmp(name, "wan1"));
}

static void source4(int fd, unsigned short port)
{
    struct sockaddr_in address;
    socklen_t length = sizeof(address);
    assert(getsockname(fd, (struct sockaddr *)&address, &length) == 0);
    assert(address.sin_family == AF_INET);
    assert(address.sin_addr.s_addr == inet_addr("198.51.100.3"));
    if (port)
        assert(ntohs(address.sin_port) == port);
}

static void inspect4(void)
{
    static const struct sockaddr_in immutable = {
        .sin_family = AF_INET, .sin_port = __constant_htons(25001),
        .sin_addr = { .s_addr = INADDR_ANY }
    };
    int fd = socket(AF_INET, SOCK_DGRAM, 0), high, local[2];
    uint32_t different = 1;
    assert(fd >= 0);
    options(fd, 0x80010000);
    assert(setsockopt(fd, SOL_SOCKET, SO_MARK, &different, sizeof(different)) == 0);
    assert(setsockopt(fd, SOL_SOCKET, SO_BINDTODEVICE, "wan0", 5) == 0);
    options(fd, 0x80010000);
    assert(bind(fd, (const struct sockaddr *)&immutable, sizeof(immutable)) == 0);
    source4(fd, 25001);
    assert(immutable.sin_addr.s_addr == INADDR_ANY);
    assert(close(fd) == 0);
    errno = 0;
    assert(close(-1) == -1 && errno == EBADF);
    errno = 0;
    assert(bind(-1, NULL, 0) == -1 && errno == EBADF);
    errno = 0;
    assert(send(-1, "x", 1, 0) == -1 && errno == EBADF);
    errno = 0;
    assert(setsockopt(-1, SOL_SOCKET, SO_MARK, &different, sizeof(different)) == -1 && errno == EBADF);
    errno = 0;
    assert(socket(AF_INET6, SOCK_STREAM, 0) == -1 && errno == EAFNOSUPPORT);

    fd = socket(AF_INET, SOCK_DGRAM, 0);
    assert(fd >= 0);
    assert(bind(fd, (const struct sockaddr *)&immutable, 1) == -1);
    errno = 0;
    assert(bind(fd, (const struct sockaddr *)&immutable, sizeof(struct sockaddr_storage) + 1) == -1 && errno == EINVAL);
    high = fcntl(fd, F_DUPFD_CLOEXEC, 1100);
    assert(high >= 1100);
    assert(close(fd) == 0);
    assert(connect(high, (const struct sockaddr *)&destination4, sizeof(destination4)) == 0);
    source4(high, 0);
    options(high, 0x80010000);
    assert(close(high) == 0);

    assert(socketpair(AF_UNIX, SOCK_STREAM, 0, local) == 0);
    assert(send(local[0], "x", 1, 0) == 1);
    assert(recv(local[1], &different, 1, 0) == 1);
    close(local[0]);
    close(local[1]);
}

static void inspect6(int emit)
{
    static const struct sockaddr_in6 immutable = { .sin6_family = AF_INET6 };
    struct sockaddr_in6 destination = { .sin6_family = AF_INET6, .sin6_port = htons(45000) };
    struct sockaddr_in6 address;
    struct in6_addr expected;
    socklen_t length = sizeof(address);
    int fd = socket(AF_INET6, SOCK_DGRAM, 0);
    assert(fd >= 0);
    assert(inet_pton(AF_INET6, "2001:db8:ffff::1", &destination.sin6_addr) == 1);
    assert(inet_pton(AF_INET6, "2001:db8:2::3", &expected) == 1);
    assert(bind(fd, (const struct sockaddr *)&immutable, sizeof(immutable)) == 0);
    assert(IN6_IS_ADDR_UNSPECIFIED(&immutable.sin6_addr));
    assert(connect(fd, (struct sockaddr *)&destination, sizeof(destination)) == 0);
    assert(getsockname(fd, (struct sockaddr *)&address, &length) == 0);
    assert(!memcmp(&address.sin6_addr, &expected, sizeof(expected)));
    options(fd, 0x80010000);
    if (emit)
        assert(send(fd, "x", 1, 0) == 1);
    close(fd);
    errno = 0;
    assert(socket(AF_INET, SOCK_STREAM, 0) == -1 && errno == EAFNOSUPPORT);
}

static void metadata(int family)
{
    struct ifreq request = { .ifr_name = "wan1" };
    struct sockaddr_storage address = { .ss_family = family };
    struct iovec vector = { .iov_base = "x", .iov_len = 1 };
    struct msghdr message = { .msg_name = &address, .msg_namelen = sizeof(address),
                             .msg_iov = &vector, .msg_iovlen = 1 };
    struct mmsghdr batch = { .msg_hdr = message };
    int fd = socket(family, SOCK_DGRAM | SOCK_CLOEXEC, 0);
    assert(fd >= 0);
    assert(ioctl(fd, SIOCGIFINDEX, &request) == 0);
    assert(request.ifr_ifindex == (int)if_nametoindex("wan1"));
    errno = 0;
    assert(bind(fd, (struct sockaddr *)&address, sizeof(address)) == -1 && errno == EAFNOSUPPORT);
    assert(connect(fd, (struct sockaddr *)&address, sizeof(address)) == -1 && errno == EAFNOSUPPORT);
    assert(send(fd, "x", 1, 0) == -1 && errno == EAFNOSUPPORT);
    assert(sendto(fd, "x", 1, 0, (struct sockaddr *)&address, sizeof(address)) == -1 && errno == EAFNOSUPPORT);
    assert(sendmsg(fd, &message, 0) == -1 && errno == EAFNOSUPPORT);
    assert(sendmmsg(fd, &batch, 1, 0) == -1 && errno == EAFNOSUPPORT);
    close(fd);
}

static int shared_socket;
static pthread_barrier_t barrier;
static void *sender(void *unused)
{
    struct sockaddr_in destination = destination4;
    int fd = dup(shared_socket);
    (void)unused;
    assert(fd >= 0);
    destination.sin_port = htons(45001);
    pthread_barrier_wait(&barrier);
    for (int i = 0; i < 100; ++i)
        assert(sendto(fd, "x", 1, 0, (struct sockaddr *)&destination, sizeof(destination)) == 1);
    source4(fd, 0);
    close(fd);
    return NULL;
}

static void resolve(int expected)
{
    struct addrinfo hints = { .ai_flags = AI_PASSIVE | AI_NUMERICSERV,
                              .ai_socktype = SOCK_DGRAM }, original = hints;
    struct addrinfo *addresses, *item;
    int found4 = 0, found6 = 0;
    assert(getaddrinfo(NULL, "53", &hints, &addresses) == 0);
    assert(!memcmp(&hints, &original, sizeof(hints)));
    for (item = addresses; item; item = item->ai_next) {
        assert(!expected || item->ai_family == expected);
        found4 |= item->ai_family == AF_INET;
        found6 |= item->ai_family == AF_INET6;
    }
    freeaddrinfo(addresses);
    assert(expected ? (expected == AF_INET ? found4 : found6) : found4 && found6);
    if (!expected)
        return;
    assert(getaddrinfo(NULL, "53", NULL, &addresses) == 0);
    for (item = addresses; item; item = item->ai_next)
        assert(item->ai_family == expected);
    freeaddrinfo(addresses);
    hints.ai_family = expected == AF_INET ? AF_INET6 : AF_INET;
    assert(getaddrinfo(NULL, "53", &hints, &addresses) != 0);
    hints.ai_flags = AI_NUMERICHOST;
    assert(getaddrinfo(expected == AF_INET ? "2001:db8::1" : "192.0.2.1",
                       NULL, &hints, &addresses) == 0);
    assert(addresses && addresses->ai_family == hints.ai_family);
    freeaddrinfo(addresses);
    hints.ai_family = AF_UNSPEC;
    hints.ai_flags = AI_NUMERICHOST | AI_V4MAPPED | AI_ALL;
    if (expected == AF_INET6)
        assert(getaddrinfo("192.0.2.1", "53", &hints, &addresses) != 0);
}

int main(int argc, char **argv)
{
    int fd;
    assert(argc >= 2);
    if (!strcmp(argv[1], "resolve4"))
        resolve(AF_INET);
    else if (!strcmp(argv[1], "resolve6"))
        resolve(AF_INET6);
    else if (!strcmp(argv[1], "resolve_both"))
        resolve(AF_UNSPEC);
    else if (!strcmp(argv[1], "inspect4"))
        inspect4();
    else if (!strcmp(argv[1], "packet4")) {
        fd = socket(AF_INET, SOCK_DGRAM, 0);
        assert(fd >= 0);
        assert(sendto(fd, "x", 1, 0, (const struct sockaddr *)&destination4, sizeof(destination4)) == 1);
        source4(fd, 0);
        close(fd);
    } else if (!strcmp(argv[1], "messages")) {
        struct sockaddr_in destination = destination4;
        struct iovec vector = { .iov_base = "x", .iov_len = 1 };
        struct msghdr message = { .msg_name = &destination, .msg_namelen = sizeof(destination),
                                 .msg_iov = &vector, .msg_iovlen = 1 };
        struct mmsghdr batch = { .msg_hdr = message };
        destination.sin_port = htons(45002);
        fd = socket(AF_INET, SOCK_DGRAM, 0);
        assert(fd >= 0);
        assert(sendmsg(fd, &message, 0) == 1);
        source4(fd, 0);
        close(fd);
        fd = socket(AF_INET, SOCK_DGRAM, 0);
        assert(fd >= 0);
        assert(sendmmsg(fd, &batch, 1, 0) == 1 && batch.msg_len == 1);
        source4(fd, 0);
        close(fd);
    } else if (!strcmp(argv[1], "inspect6"))
        inspect6(0);
    else if (!strcmp(argv[1], "packet6"))
        inspect6(1);
    else if (!strcmp(argv[1], "metadata4"))
        metadata(AF_INET);
    else if (!strcmp(argv[1], "metadata6"))
        metadata(AF_INET6);
    else if (!strcmp(argv[1], "threads")) {
        pthread_t threads[8];
        shared_socket = socket(AF_INET, SOCK_DGRAM, 0);
        assert(shared_socket >= 0);
        assert(pthread_barrier_init(&barrier, NULL, 8) == 0);
        for (unsigned i = 0; i < 8; ++i)
            assert(pthread_create(&threads[i], NULL, sender, NULL) == 0);
        for (unsigned i = 0; i < 8; ++i)
            assert(pthread_join(threads[i], NULL) == 0);
        close(shared_socket);
    } else if (!strcmp(argv[1], "packet_socket")) {
        const struct sockaddr_ll request = { .sll_family = AF_PACKET, .sll_protocol = htons(ETH_P_ARP),
                                             .sll_ifindex = if_nametoindex("wan0") };
        struct sockaddr_ll actual;
        socklen_t length = sizeof(actual);
        fd = socket(AF_PACKET, SOCK_DGRAM, htons(ETH_P_ARP));
        assert(fd >= 0);
        assert(bind(fd, (const struct sockaddr *)&request, sizeof(request)) == 0);
        assert(request.sll_ifindex == (int)if_nametoindex("wan0"));
        assert(getsockname(fd, (struct sockaddr *)&actual, &length) == 0);
        assert(actual.sll_ifindex == (int)if_nametoindex("wan1"));
        close(fd);
    } else if (!strcmp(argv[1], "zero_mark")) {
        uint32_t different = 1;
        fd = socket(AF_INET, SOCK_DGRAM, 0);
        assert(fd >= 0);
        assert(setsockopt(fd, SOL_SOCKET, SO_MARK, &different, sizeof(different)) == 0);
        options(fd, 0);
        close(fd);
    } else if (!strcmp(argv[1], "optional")) {
        uint32_t value = 123, actual;
        socklen_t length = sizeof(actual);
        fd = socket(AF_INET, SOCK_DGRAM, 0);
        assert(fd >= 0);
        assert(setsockopt(fd, SOL_SOCKET, SO_MARK, &value, sizeof(value)) == 0);
        assert(getsockopt(fd, SOL_SOCKET, SO_MARK, &actual, &length) == 0 && actual == value);
        assert(setsockopt(fd, SOL_SOCKET, SO_BINDTODEVICE, "wan0", 5) == 0);
        close(fd);
    } else if (!strcmp(argv[1], "tcp_server")) {
        struct sockaddr_in local = { .sin_family = AF_INET, .sin_port = htons(45003) }, peer;
        socklen_t length = sizeof(peer);
        char byte;
        int accepted;
        FILE *ready;
        alarm(5);
        assert(argc == 3);
        fd = socket(AF_INET, SOCK_STREAM, 0);
        assert(fd >= 0);
        assert(bind(fd, (struct sockaddr *)&local, sizeof(local)) == 0);
        assert(listen(fd, 1) == 0);
        ready = fopen(argv[2], "w");
        assert(ready && fclose(ready) == 0);
        accepted = accept(fd, (struct sockaddr *)&peer, &length);
        assert(accepted >= 0);
        assert(peer.sin_addr.s_addr == inet_addr("127.0.0.2"));
        assert(recv(accepted, &byte, 1, 0) == 1);
        assert(send(accepted, &byte, 1, 0) == 1);
        close(accepted);
        close(fd);
    } else if (!strcmp(argv[1], "tcp_client")) {
        struct sockaddr_in peer = { .sin_family = AF_INET, .sin_port = htons(45003),
                                    .sin_addr = { .s_addr = inet_addr("127.0.0.1") } };
        char byte;
        alarm(5);
        fd = socket(AF_INET, SOCK_STREAM, 0);
        assert(fd >= 0);
        assert(connect(fd, (struct sockaddr *)&peer, sizeof(peer)) == 0);
        assert(send(fd, "x", 1, 0) == 1);
        assert(recv(fd, &byte, 1, 0) == 1 && byte == 'x');
        close(fd);
    } else if (!strcmp(argv[1], "error")) {
        int expected;
        assert(argc == 3);
        expected = !strcmp(argv[2], "ENODEV") ? ENODEV :
                   !strcmp(argv[2], "ENAMETOOLONG") ? ENAMETOOLONG : EINVAL;
        errno = 0;
        assert(socket(AF_INET, SOCK_DGRAM, 0) == -1 && errno == expected);
        assert(socket(AF_UNIX, SOCK_STREAM, 0) >= 0);
    } else
        abort();
    return 0;
}
C
"${CC:-cc}" -std=gnu11 -O2 -Wall -Wextra -Werror -pthread "$TEST_ROOT/probe.c" -o "$TEST_ROOT/probe"
unshare -Urn /bin/sh "$0" --inside "$TEST_ROOT"
