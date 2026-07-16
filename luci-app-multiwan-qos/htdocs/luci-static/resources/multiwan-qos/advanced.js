'use strict';
'require view';
'require form';
'require ui';
'require uci';
'require fs';
'require rpc';

var callCpuNicDiagnostics = rpc.declare({
    object: 'luci.multiwan_qos_stats',
    method: 'getCpuNicDiagnostics',
    expect: {}
});

// SFO warning for dynamic rule parameters
function addSfoWarning(description, paramName) {
    var dynamicParams = [
        'UDP_RATE_LIMIT_ENABLED',
        'TCP_UPGRADE_ENABLED',
        'TCP_DOWNPRIO_INITIAL_ENABLED',
        'TCP_DOWNPRIO_SUSTAINED_ENABLED'
    ];

    if (dynamicParams.includes(paramName)) {
        var sfoEnabled = uci.get('firewall', '@defaults[0]', 'flow_offloading') === '1';
        if (sfoEnabled) {
            return description + ' ⚠ May not work with Software Flow Offloading enabled';
        }
    }
    return description;
}

return view.extend({
    handleSaveApply: function (ev) {
        return this.handleSave(ev)
            .then(() => ui.changes.apply())
            .then(() => uci.load('multiwan-qos'))
            .then(() => uci.get_first('multiwan-qos', 'global', 'enabled'))
            .then(enabled => {
                if (enabled === '0') {
                    return fs.exec_direct('/etc/init.d/multiwan-qos', ['stop']);
                } else {
                    return fs.exec_direct('/etc/init.d/multiwan-qos', ['restart']);
                }
            })
            .then(() => {
                ui.hideModal();
                window.location.reload();
            })
            .catch(err => {
                ui.hideModal();
                ui.addNotification(null, E('p', _('Failed to save settings or update MultiWAN QoS service: ') + err.message));
            });
    },

    render: function () {
        return Promise.all([
            uci.load('multiwan-qos'),
            uci.load('firewall')
        ]).then(() => {
            var m, s, o;

            m = new form.Map('multiwan-qos', _('MultiWAN QoS Advanced Settings'), _('Configure advanced settings for MultiWAN QoS.'));



            // Advanced Settings
            s = m.section(form.NamedSection, 'advanced', 'advanced', _('Advanced Settings'));
            s.anonymous = true;

            function createOption(name, title, description, placeholder, datatype) {
                var opt = s.option(form.Value, name, title, description);
                opt.datatype = datatype || 'string';
                opt.rmempty = true;
                opt.placeholder = placeholder;

                if (datatype === 'uinteger') {
                    opt.validate = function (section_id, value) {
                        if (value === '' || value === null) return true;
                        if (!/^\d+$/.test(value)) return _('Must be a non-negative integer or empty');
                        return true;
                    };
                }
                if (datatype === 'integer') {
                    opt.validate = function (section_id, value) {
                        if (value === '' || value === null) return true;
                        if (!/^-?\d+$/.test(value)) return _('Must be an integer or empty');
                        return true;
                    };
                }
                return opt;
            }

            o = s.option(form.Flag, 'PRESERVE_CONFIG_FILES', _('Preserve Config Files'), _('Preserve configuration files during system upgrade'));
            o.rmempty = false;

            o = s.option(form.Flag, 'WASHDSCPUP', _('Wash DSCP Egress'), _('Sets DSCP to CS0 for outgoing packets after classification'));
            o.rmempty = false;

            o = s.option(form.Flag, 'WASHDSCPDOWN', _('Wash DSCP Ingress'), _('Sets DSCP to CS0 for incoming packets before classification'));
            o.rmempty = false;

            o = s.option(form.Flag, 'WASHDSCPLAN', _('Wash LAN DSCP'), _('Strips DSCP from LAN-originated packets before classification. Prevents LAN devices from self-tagging as EF to gain Realtime priority.'));
            o.rmempty = false;

            o = s.option(form.Flag, 'WASHDSCPDOWNDELIVERY', _('Clean Delivery to LAN'), _('Washes DSCP to CS0 on download packets just before they reach your LAN devices. Ensures clean delivery after shaping is complete.'));
            o.rmempty = false;

            o = s.option(form.Flag, 'DOWNLOAD_IFB_STAB', _('Download IFB STAB'), _('Apply link-layer overhead accounting to download IFB roots for HFSC, HTB, and Hybrid. Pure CAKE is unchanged because it already applies link parameters directly.'));
            o.rmempty = false;
            o.default = '0';

            o = s.option(form.Flag, 'DISABLE_QOS_OFFLOADS', _('Disable QoS Offloads'), _('Disable GRO, GSO, TSO, rx-gro-list, tx-udp-segmentation, and hardware TC offload on managed WAN and IFB devices for accurate QoS scheduling.'));
            o.rmempty = false;
            o.default = '1';

            o = s.option(form.Value, 'OFFLOAD_EXTRA_DEVICES', _('Extra Offload Devices'), _('Optional space-separated physical devices to apply QoS offload control to, such as PPPoE lower ports.'));
            o.placeholder = 'eth0 eth1 eth2';
            o.rmempty = true;
            o.depends('DISABLE_QOS_OFFLOADS', '1');

            o = s.option(form.Flag, 'ENABLE_CPU_NIC_DIAGNOSTICS', _('CPU and NIC Diagnostics'), _('Allow an on-demand, read-only one-second sample of network softirqs, softnet pressure, queue masks, NIC offloads, and interface error counters.'));
            o.rmempty = false;
            o.default = '0';

            o = s.option(form.Button, '_run_cpu_nic_diagnostics', _('Diagnostics Snapshot'));
            o.inputstyle = 'action';
            o.inputtitle = _('Run Snapshot');
            o.depends('ENABLE_CPU_NIC_DIAGNOSTICS', '1');
            o.onclick = function () {
                ui.showModal(_('CPU and NIC Diagnostics'), [
                    E('p', { 'class': 'spinning' }, _('Sampling for one second...'))
                ]);

                return callCpuNicDiagnostics().then(function (result) {
                    ui.showModal(_('CPU and NIC Diagnostics'), [
                        E('pre', {
                            'style': 'max-height: 65vh; overflow: auto; white-space: pre-wrap;'
                        }, [ JSON.stringify(result, null, 2) ]),
                        E('div', { 'class': 'right' }, [
                            E('button', {
                                'class': 'btn',
                                'click': ui.hideModal
                            }, [ _('Close') ])
                        ])
                    ]);
                }).catch(function (err) {
                    ui.hideModal();
                    ui.addNotification(null, E('p', _('Diagnostics failed: ') + err.message), 'error');
                });
            };

            createOption('BWMAXRATIO', _('Bandwidth Max Ratio'), _('Max download/upload ratio to prevent upstream congestion'), _('Default: 20'), 'uinteger');
            // Note: ACKRATE has been moved to per-interface settings

            o = s.option(form.Flag, 'UDP_RATE_LIMIT_ENABLED', _('Enable UDP Rate Limit'), _(addSfoWarning('Moves UDP traffic exceeding 450 pps to lower priority', 'UDP_RATE_LIMIT_ENABLED')));
            o.rmempty = false;

            o = s.option(form.Flag, 'TCP_UPGRADE_ENABLED', _('Boost Low-Volume TCP Traffic'), _(addSfoWarning('Upgrade DSCP to AF42 for TCP connections with less than 150 packets per second. This can improve responsiveness for interactive TCP services like SSH, web browsing, and instant messaging.', 'TCP_UPGRADE_ENABLED')));
            o.rmempty = false;
            o.default = '1';

            o = s.option(form.Flag, 'TCP_DOWNPRIO_INITIAL_ENABLED', _('Enable Initial TCP Down-Prioritization'), _(addSfoWarning('Moves the first ~500ms of TCP traffic (except CS1) to CS0 to prevent initial bursts', 'TCP_DOWNPRIO_INITIAL_ENABLED')));
            o.rmempty = false;
            o.default = '1';

            o = s.option(form.Flag, 'TCP_DOWNPRIO_SUSTAINED_ENABLED', _('Enable Sustained TCP Down-Prioritization'), _(addSfoWarning('Moves TCP flows past a cumulative conntrack byte threshold to CS1 (Bulk). This threshold is not a direct congestion measurement and can demote long-lived connections even when the link is not congested.', 'TCP_DOWNPRIO_SUSTAINED_ENABLED')));
            o.rmempty = false;
            o.default = '0';

            createOption('UDPBULKPORT', _('UDP Bulk Ports'), _('Specify UDP ports for bulk traffic'), _('Default: none'));
            createOption('TCPBULKPORT', _('TCP Bulk Ports'), _('Specify TCP ports for bulk traffic'), _('Default: none'));

            o = s.option(form.Value, 'MSS', _('TCP MSS'), _('Maximum Segment Size for TCP connections. This setting is only active when the upload or download bandwidth is less than 3000 kbit/s. Leave empty to use the default value. Valid range: 536-1500'), _('Default: 536'), 'uinteger');
            o.placeholder = 'Default: 536';
            o.validate = function (section_id, value) {
                if (value === '' || value === null)
                    return true;

                if (!/^\d+$/.test(value))
                    return _('Must be a number');

                let num = Number(value);
                if (num < 536 || num > 1500)
                    return _('Must be between 536 and 1500');

                return true;
            };

            o = s.option(form.ListValue, 'NFT_HOOK', _('Nftables Hook'), _('Select the nftables hook point for the dscptag chain'));
            o.value('forward', _('forward'));
            o.value('postrouting', _('postrouting'));
            o.default = 'forward';
            o.rmempty = false;

            createOption('NFT_PRIORITY', _('Nftables Priority'), _('Set the priority for the nftables chain. Lower values are processed earlier. Default is 0 | mangle is -150.'), _('0'), 'integer');

            o = s.option(form.Flag, 'MULTICAST_POLICING', _('Multicast Policing'), _('Rate-limit multicast (IPTV) traffic on the LAN interface to prevent flooding on unmanaged switches. Only affects multicast — gaming and other unicast traffic is untouched.'));
            o.rmempty = false;

            o = s.option(form.Value, 'MULTICAST_RATE', _('Multicast Rate (kbit/s)'), _('Maximum rate for multicast traffic on LAN. Default: 13000 (13 Mbps). Adjust based on your IPTV bandwidth.'));
            o.placeholder = '13000';
            o.datatype = 'uinteger';
            o.rmempty = true;
            o.depends('MULTICAST_POLICING', '1');

            o = s.option(form.Value, 'MULTICAST_LAN_DEVICE', _('LAN Device'), _('LAN interface to apply multicast policing on. Default: eth0'));
            o.placeholder = 'eth0';
            o.rmempty = true;
            o.depends('MULTICAST_POLICING', '1');

            return m.render();
        });
    }
});
