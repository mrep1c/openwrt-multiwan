'use strict';
'require view';
'require form';
'require ui';
'require uci';
'require rpc';
'require fs';
'require poll';
'require tools.widgets as widgets';

const UI_VERSION = '1.0.47';
const UI_UPD_CHANNEL = 'release';

var callInitAction = rpc.declare({
    object: 'luci',
    method: 'setInitAction',
    params: ['name', 'action'],
    expect: { result: false }
});

var callAgentStatus = rpc.declare({
    object: 'luci.multiwan_qos',
    method: 'getAgentStatus',
    expect: {}
});

function createStatusText(status, text) {
    var colors = {
        'current': '#4CAF50',  // Green
        'update': '#FF5252',   // Red
        'error': '#FFC107',    // Yellow
        'unknown': '#9E9E9E'   // Gray
    };

    var icons = {
        'current': '✓ ',
        'update': '↑ ',
        'error': '⚠ ',
        'unknown': '? '
    };

    return E('span', {
        'style': 'color: ' + colors[status] + '; font-weight: bold; font-size: 13px;'
    }, icons[status] + text);
}

var healthCheckData = null;
var agentStatusData = null;


return view.extend({
    agentStatusPollHandler: null,

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

    load: function () {
        return Promise.all([
            uci.load('multiwan-qos'),
            uci.load('firewall'),
            this.fetchHealthCheck(),
            this.fetchAgentStatus()
        ]).catch(error => {
            console.error('Error in load function:', error);
            ui.addNotification(null, E('p', _('Error loading initial data: %s').format(error.message || error)), 'error');
            return [null, null, null];
        });
    },

    fetchHealthCheck: function () {
        return fs.exec_direct('/etc/init.d/multiwan-qos', ['health_check'])
            .then((res) => {
                var output = res.trim();
                // Parse the full status string (everything between status= and ;errors=)
                var statusMatch = output.match(/status=(.*?);errors=/);
                var errorsMatch = output.match(/errors=(\d+)$/);

                var statusString = statusMatch ? statusMatch[1] : 'Unknown';
                var errorsCount = errorsMatch ? parseInt(errorsMatch[1]) : 0;

                var statusSegments = statusString.split(';');
                var detailsArray = [];
                statusSegments.forEach(function (segment) {
                    if (!segment) return;
                    detailsArray.push(segment);
                });

                healthCheckData = {
                    details: detailsArray,
                    errors: errorsCount
                };
                // console.log("Health check data loaded successfully:", healthCheckData);
            })
            .catch((err) => {
                console.error('Health check failed:', err);
                healthCheckData = {
                    details: ['Health check failed: ' + err],
                    errors: 1
                };
            });
    },

    fetchAgentStatus: function () {
        return callAgentStatus()
            .then((res) => {
                agentStatusData = res || null;
            })
            .catch((err) => {
                agentStatusData = {
                    error: err && err.message ? err.message : String(err || 'unknown')
                };
            });
    },

    render: function () {
        var m, s_info, s_status, o;
        var view = this;

        m = new form.Map('multiwan-qos', _(''),
            _('For detailed setup instructions and advanced configuration options, please check the ') +
            '<a href="https://github.com/mrep1c/openwrt-multiwan/blob/main/README.md" target="_blank" style="color: #1976d2; text-decoration: none;">README</a>.');

        // Version and update section removed

        // Section, also targeting 'global' but with a UI title for grouping
        s_status = m.section(form.NamedSection, 'global', 'global', _('Service Status & Control'));

        // Service Status (Health Check)
        o = s_status.option(form.DummyValue, '_health_check', _(''));
        o.rawhtml = true;
        o.render = function (section_id) {
            var container = E('div');

            function setContent(node, child) {
                while (node.firstChild)
                    node.removeChild(node.firstChild);
                node.appendChild(child);
            }

            function iconForStatus(status) {
                if (status === 'ready' || status === 'connected' || status === 'enabled' ||
                    status === 'started' || status === 'ok')
                    return 'OK';
                if (status === 'disabled' || status === 'stopped')
                    return '-';
                if (status === 'failed')
                    return 'X';
                return '!';
            }

            function colorForStatus(status) {
                if (status === 'ready' || status === 'connected' || status === 'enabled' ||
                    status === 'started' || status === 'ok')
                    return 'green';
                if (status === 'disabled' || status === 'stopped')
                    return '#777';
                if (status === 'failed')
                    return 'red';
                return 'orange';
            }

            function displayStatusText(status) {
                status = String(status || 'unknown');
                return status.charAt(0).toUpperCase() + status.slice(1);
            }

            function buildStatus() {
                if (!healthCheckData) {
                    return E('div', { 'class': 'cbi-value' }, [
                        E('label', { 'class': 'cbi-value-title' }, _('Service Status')),
                        E('div', { 'class': 'cbi-value-field' }, _('Loading health check status...'))
                    ]);
                }

                var statusHtml = E('div', {
                    'class': 'health-status',
                    'style': 'display: flex; gap: 16px; align-items: center; flex-wrap: wrap;'
                });
                var statusMap = {};

                healthCheckData.details.forEach(function (detail) {
                    if (!detail)
                        return;
                    var parts = detail.split(':');
                    var type = String(parts[0] || '').trim().toLowerCase();
                    var status = String(parts[1] || 'unknown').trim().toLowerCase();
                    if (type)
                        statusMap[type] = status;
                });

                healthCheckData.details.forEach(function (detail) {
                    if (!detail)
                        return;
                    var parts = detail.split(':');
                    var type = String(parts[0] || '').trim().toLowerCase();
                    var status = String(parts[1] || 'unknown').trim().toLowerCase();

                    if (type === 'pc')
                        return;

                    var displayType = type.charAt(0).toUpperCase() + type.slice(1);
                    var displayStatus = status;

                    if (type === 'agent') {
                        displayType = 'PC Agent';
                        if (agentStatusData && !agentStatusData.error && agentStatusData.pc_state) {
                            displayStatus = agentStatusData.pc_state;
                        } else if (status === 'ready') {
                            displayStatus = statusMap.pc === 'connected' ? 'connected' :
                                (statusMap.pc === 'stale' ? 'stale' : 'ready');
                        }
                    }

                    var color = colorForStatus(displayStatus);
                    statusHtml.appendChild(
                        E('div', { 'style': 'display: flex; align-items: center; gap: 4px;' }, [
                            E('span', {
                                'style': 'color: ' + color + '; font-size: 15px; font-weight: bold; min-width: 22px;'
                            }, iconForStatus(displayStatus)),
                            E('span', {
                                'style': 'font-size: 13px; color: #666;'
                            }, _('%s: %s').format(_(displayType), _(displayStatusText(displayStatus))))
                        ])
                    );
                });

                return E('div', { 'class': 'cbi-value' }, [
                    E('label', { 'class': 'cbi-value-title' }, _('Service Status')),
                    E('div', { 'class': 'cbi-value-field' }, statusHtml)
                ]);
            }

            function refreshStatus() {
                return Promise.all([
                    view.fetchHealthCheck(),
                    view.fetchAgentStatus()
                ]).then(function () {
                    setContent(container, buildStatus());
                }).catch(function () {
                    setContent(container, buildStatus());
                });
            }

            setContent(container, buildStatus());

            if (!view.agentStatusPollHandler) {
                view.agentStatusPollHandler = refreshStatus;
                poll.add(view.agentStatusPollHandler, 5);
            }

            return container;
        };

        // Service Control buttons
        o = s_status.option(form.DummyValue, '_buttons', _(''));
        o.rawhtml = true;
        o.render = function (section_id) {
            var buttonStyle = 'button cbi-button';
            return E('div', { 'class': 'cbi-value' }, [
                E('label', { 'class': 'cbi-value-title' }, _('Service Control')),
                E('div', { 'class': 'cbi-value-field' }, [
                    E('button', {
                        'class': buttonStyle + ' cbi-button-apply',
                        'click': ui.createHandlerFn(this, function () {
                            return fs.exec_direct('/etc/init.d/multiwan-qos', ['start'])
                                .then(function () {
                                    ui.addNotification(null, E('p', _('MultiWAN QoS started')), 'success');
                                    window.setTimeout(function () { location.reload(); }, 1000);
                                })
                                .catch(function (e) { ui.addNotification(null, E('p', _('Failed to start MultiWAN QoS: ') + e), 'error'); });
                        })
                    }, _('Start')),
                    ' ',
                    E('button', {
                        'class': buttonStyle + ' cbi-button-neutral',
                        'click': ui.createHandlerFn(this, function () {
                            return fs.exec_direct('/etc/init.d/multiwan-qos', ['restart'])
                                .then(function () {
                                    ui.addNotification(null, E('p', _('MultiWAN QoS restarted')), 'success');
                                    window.setTimeout(function () { location.reload(); }, 1000);
                                })
                                .catch(function (e) { ui.addNotification(null, E('p', _('Failed to restart MultiWAN QoS: ') + e), 'error'); });
                        })
                    }, _('Restart')),
                    ' ',
                    E('button', {
                        'class': buttonStyle + ' cbi-button-reset',
                        'click': ui.createHandlerFn(this, function () {
                            return fs.exec_direct('/etc/init.d/multiwan-qos', ['stop'])
                                .then(function () {
                                    ui.addNotification(null, E('p', _('MultiWAN QoS stopped')), 'success');
                                    window.setTimeout(function () { location.reload(); }, 1000);
                                })
                                .catch(function (e) { ui.addNotification(null, E('p', _('Failed to stop MultiWAN QoS: ') + e), 'error'); });
                        })
                    }, _('Stop'))
                ])
            ]);
        };

        // Auto Setup Button
        o = s_status.option(form.Button, '_auto_setup', _('Auto Setup'));
        o.inputstyle = 'apply';
        o.inputtitle = _('Start Auto Setup');
        o.onclick = ui.createHandlerFn(this, function () {
            ui.showModal(_('Auto Setup'), [
                E('p', { 'style': 'color: orange; font-weight: bold;' }, _('Auto Setup can configure one OpenWrt WAN network at a time.')),
                E('p', _('Run /etc/init.d/multiwan-qos auto_setup <network> from SSH, or configure multiple interfaces manually here.')),
                E('div', { 'class': 'right' }, [
                    E('button', {
                        'class': 'btn',
                        'click': ui.hideModal
                    }, _('Close'))
                ])
            ]);
        });


        // Interfaces
        let s_interfaces = m.section(form.TypedSection, 'interface', _('Interfaces'), _('Configure your WAN interfaces.'));
        s_interfaces.addremove = true;
        s_interfaces.anonymous = true;

        // Fix for dark theme - inherit background colors
        s_interfaces.renderSectionAdd = function (extra_class) {
            var el = form.TypedSection.prototype.renderSectionAdd.apply(this, arguments);
            if (el) {
                el.style.backgroundColor = 'inherit';
                el.style.color = 'inherit';
            }
            return el;
        };



        o = s_interfaces.option(form.Flag, 'enabled', _('Enabled'));
        o.default = '1';

        o = s_interfaces.option(widgets.DeviceSelect, 'device', _('Interface'), _('Select the WAN interface (device)'));
        o.rmempty = false;

        o = s_interfaces.option(form.Value, 'download', _('Download Rate (kbps)'), _('Set the download rate in kbps'));
        o.datatype = 'uinteger';
        o.rmempty = false;

        o = s_interfaces.option(form.Value, 'upload', _('Upload Rate (kbps)'), _('Set the upload rate in kbps'));
        o.datatype = 'uinteger';
        o.rmempty = false;

        o = s_interfaces.option(form.ListValue, 'qdisc', _('Queueing Discipline'));
        o.value('hfsc', _('HFSC'));
        o.value('cake', _('CAKE'));
        o.value('hybrid', _('Hybrid'));
        o.value('htb', _('HTB'));
        o.default = 'hfsc';

        // Link Layer Settings (Moved from Advanced)
        o = s_interfaces.option(form.ListValue, 'preset', _('Link Type'), _('Overhead calculation preset. Use GPON presets for fiber ONT/OLT PPPoE bridges; use Ethernet presets for copper/Ethernet bottlenecks.'));
        o.value('ethernet', _('Ethernet (40B/38B)'));
        o.value('pppoe-ethernet', _('PPPoE over Ethernet (46B, MPU 84)'));
        o.value('pppoe-vlan-ethernet', _('PPPoE + VLAN over Ethernet (50B, MPU 84)'));
        o.value('pppoe-gpon', _('PPPoE over GPON (31B, MPU 69)'));
        o.value('pppoe-vlan-gpon', _('PPPoE + VLAN over GPON (35B, MPU 69)'));
        o.value('pppoe-vlan-gpon-conservative', _('PPPoE + VLAN over GPON conservative (39B, MPU 73)'));
        o.value('docsis', _('Cable DOCSIS (25B)'));
        o.value('atm', _('DSL ATM/ADSL (44B)'));
        o.value('cake-ethernet', _('[CAKE] Ethernet (38B)'));
        o.value('raw', _('Raw (No overhead)'));
        o.default = 'ethernet';

        o = s_interfaces.option(form.Value, 'overhead', _('Manual Overhead'), _('Override preset overhead (bytes). Leave empty to use the selected preset default.'));
        o.datatype = 'uinteger';
        o.placeholder = 'Auto';

        o = s_interfaces.option(form.Value, 'mpu', _('MPU'), _('Override preset minimum packet unit (bytes). Leave empty to use the selected preset default. Standard GPON PPPoE presets use 69; the conservative VLAN/GPON preset uses 73.'));
        o.datatype = 'uinteger';
        o.placeholder = 'Auto';

        o = s_interfaces.option(form.Value, 'ackrate', _('ACK Rate'), _('TCP ACK rate limit in packets/second. Helps prevent ACK flooding on asymmetric connections. Set to 0 to disable.'));
        o.datatype = 'uinteger';
        o.placeholder = _('Auto (5% of upload)');

        return m.render();
    }
});

function updateMultiwanQos() {
    // Implement the update logic here
    ui.showModal(_('Updating MultiWAN QoS'), [
        E('p', { 'class': 'spinning' }, _('Updating MultiWAN QoS. Please wait...'))
    ]);

    // Simulating an update process
    setTimeout(function () {
        ui.hideModal();
        window.location.reload();
    }, 5000);
}
