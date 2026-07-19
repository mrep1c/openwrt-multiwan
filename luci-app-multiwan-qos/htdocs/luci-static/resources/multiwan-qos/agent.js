'use strict';
'require view';
'require form';
'require ui';
'require uci';
'require rpc';
'require fs';
'require poll';

var callAgentStatus = rpc.declare({
    object: 'luci.multiwan_qos',
    method: 'getAgentStatus',
    expect: {}
});

return view.extend({
    agentPollHandler: null,
    agentPollInterval: null,

    handleSaveApply: function (ev) {
        return this.handleSave(ev)
            .then(() => ui.changes.apply())
            .then(() => uci.load('multiwan-qos'))
            .then(() => uci.get('multiwan-qos', 'global', 'enabled'))
            .then(enabled => {
                if (enabled === '1')
                    return fs.exec_direct('/etc/init.d/multiwan-qos', ['restart']);
                return Promise.resolve();
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
            uci.load('multiwan-qos')
        ]).then(() => {
            var m, s, o;
            var view = this;
            var agentSection = 'agent';

            function getApiKeyInput() {
                return document.getElementById('widget.cbid.multiwan_qos.agent.api_key') ||
                    document.querySelector('input[name="cbid.multiwan_qos.agent.api_key"]') ||
                    document.querySelector('input[id$=".api_key"]') ||
                    document.querySelector('input[name$=".api_key"]') ||
                    document.querySelector('input[data-name="api_key"]') ||
                    document.querySelector('#cbi-multiwan-qos-agent-api_key input');
            }

            function getApiKeyValue() {
                var input = getApiKeyInput();
                if (input)
                    return input.value || '';

                return uci.get('multiwan-qos', agentSection, 'api_key') || '';
            }

            function fireInputEvent(input, type) {
                var ev;

                if (typeof Event === 'function') {
                    ev = new Event(type, { bubbles: true });
                } else {
                    ev = document.createEvent('HTMLEvents');
                    ev.initEvent(type, true, false);
                }

                input.dispatchEvent(ev);
            }

            function setApiKeyValue(key) {
                var input = getApiKeyInput();

                uci.set('multiwan-qos', agentSection, 'api_key', key);

                if (input) {
                    input.value = key;
                    fireInputEvent(input, 'input');
                    fireInputEvent(input, 'change');
                    return true;
                }

                return false;
            }

            function generateApiKey() {
                var bytes = new Uint8Array(32);
                var key = '';

                if (window.crypto && window.crypto.getRandomValues) {
                    window.crypto.getRandomValues(bytes);
                } else {
                    for (var i = 0; i < bytes.length; i++)
                        bytes[i] = Math.floor(Math.random() * 256);
                }

                for (var j = 0; j < bytes.length; j++)
                    key += ('0' + bytes[j].toString(16)).slice(-2);

                return key;
            }

            function copyText(text) {
                if (navigator.clipboard && navigator.clipboard.writeText)
                    return navigator.clipboard.writeText(text);

                var area = E('textarea', {
                    'style': 'position: fixed; left: -9999px; top: 0; opacity: 0;'
                }, text);

                document.body.appendChild(area);
                area.focus();
                area.select();

                try {
                    if (document.execCommand('copy'))
                        return Promise.resolve();
                } catch (e) {
                } finally {
                    document.body.removeChild(area);
                }

                return Promise.reject(new Error('clipboard unavailable'));
            }

            function setContent(node, child) {
                while (node.firstChild)
                    node.removeChild(node.firstChild);
                node.appendChild(child);
            }

            function normalizeRules(data) {
                if (!data || !data.rules)
                    return [];
                if (Array.isArray(data.rules))
                    return data.rules;
                return Object.keys(data.rules).map(function (key) {
                    return data.rules[key];
                });
            }

            function statusLabel(status) {
                var labels = {
                    disabled: _('Disabled'),
                    ready: _('Ready'),
                    connected: _('Connected'),
                    stale: _('Stale'),
                    waiting: _('Waiting'),
                    failed: _('Failed')
                };
                return labels[status] || _('Unknown');
            }

            function statusColor(status) {
                if (status === 'connected' || status === 'ready')
                    return 'green';
                if (status === 'disabled')
                    return '#777';
                if (status === 'failed')
                    return 'red';
                return 'orange';
            }

            function statusIcon(status) {
                if (status === 'connected' || status === 'ready')
                    return 'OK';
                if (status === 'disabled')
                    return '-';
                if (status === 'failed')
                    return 'X';
                return '!';
            }

            function formatBytes(bytes) {
                bytes = Number(bytes || 0);
                if (bytes < 1024)
                    return '%d B'.format(bytes);
                if (bytes < 1048576)
                    return (bytes / 1024).toFixed(1) + ' KiB';
                return (bytes / 1048576).toFixed(1) + ' MiB';
            }

            function directionLabel(direction) {
                if (direction === 'UP')
                    return _('Upload');
                if (direction === 'DN')
                    return _('Download');
                return _('Unknown');
            }

            function shouldFastAgentPoll(data) {
                return data &&
                    data.enabled &&
                    data.chain_exists &&
                    data.pc_state === 'connected' &&
                    Number(data.rule_count || 0) === 0 &&
                    (data.last_seen_age == null || Number(data.last_seen_age || 0) < 90);
            }

            function renderAgentPanel(data) {
                data = data || {};
                var status = data.pc_state || 'unknown';
                var color = statusColor(status);
                var rules = normalizeRules(data);
                var panel = E('div');

                panel.appendChild(E('div', { 'class': 'cbi-value' }, [
                    E('label', { 'class': 'cbi-value-title' }, _('PC Agent')),
                    E('div', { 'class': 'cbi-value-field' }, [
                        E('span', {
                            'style': 'color: ' + color + '; font-weight: bold; margin-right: 6px;'
                        }, statusIcon(status)),
                        E('span', { 'style': 'color: ' + color + '; font-weight: bold;' },
                            statusLabel(status)),
                        data.last_seen_age != null
                            ? E('span', { 'style': 'color: #777; margin-left: 8px;' },
                                _('last seen %ds ago').format(data.last_seen_age))
                            : ''
                    ])
                ]));

                if (!data.enabled) {
                    panel.appendChild(E('div', { 'class': 'cbi-value' }, [
                        E('label', { 'class': 'cbi-value-title' }, _('Active Rules')),
                        E('div', { 'class': 'cbi-value-field' },
                            E('span', { 'style': 'color: #777;' }, _('PC Agent support is disabled.')))
                    ]));
                    return panel;
                }

                if (!data.chain_exists) {
                    panel.appendChild(E('div', { 'class': 'cbi-value' }, [
                        E('label', { 'class': 'cbi-value-title' }, _('Agent Chain')),
                        E('div', { 'class': 'cbi-value-field' }, [
                            E('span', { 'style': 'color: orange;' },
                                _('Agent chain not found. Enable the agent and restart MultiWAN QoS.'))
                        ])
                    ]));
                    return panel;
                }

                if (rules.length === 0) {
                    var emptyBody = E('div', { 'class': 'cbi-value-field' }, [
                        E('span', { 'style': 'color: #9E9E9E; font-style: italic;' },
                            _('No active PC-agent game rules.'))
                    ]);
                    if (data.parse_warning || Number(data.non_agent_rule_count || 0) > 0) {
                        emptyBody.appendChild(E('div', { 'style': 'color: orange; margin-top: 6px;' },
                            data.parse_warning || _('multiwan_qos_agent contains non-agent rules; ignored.')));
                        emptyBody.appendChild(E('div', { 'style': 'color: #777; margin-top: 4px;' },
                            _('Raw rules: %d, agent-owned rules: %d, non-agent rules: %d').format(
                                Number(data.raw_rule_count || 0),
                                Number(data.agent_rule_count || 0),
                                Number(data.non_agent_rule_count || 0)
                            )));
                    }
                    panel.appendChild(E('div', { 'class': 'cbi-value' }, [
                        E('label', { 'class': 'cbi-value-title' }, _('Active Rules (0)')),
                        emptyBody
                    ]));
                    return panel;
                }

                var table = E('table', { 'class': 'table cbi-section-table' });
                var headerRow = E('tr', { 'class': 'tr table-titles' });
                headerRow.appendChild(E('th', { 'class': 'th' }, _('Game')));
                headerRow.appendChild(E('th', { 'class': 'th' }, _('Direction')));
                headerRow.appendChild(E('th', { 'class': 'th' }, _('DSCP')));
                headerRow.appendChild(E('th', { 'class': 'th' }, _('Packets')));
                headerRow.appendChild(E('th', { 'class': 'th' }, _('Bytes')));
                headerRow.appendChild(E('th', { 'class': 'th' }, _('Rule')));
                table.appendChild(headerRow);

                rules.forEach(function (rule) {
                    var row = E('tr', { 'class': 'tr' });
                    row.appendChild(E('td', { 'class': 'td' }, rule.game || _('Unknown')));
                    row.appendChild(E('td', { 'class': 'td' }, directionLabel(rule.direction)));
                    row.appendChild(E('td', { 'class': 'td' }, String(rule.dscp || '').toUpperCase()));
                    row.appendChild(E('td', { 'class': 'td' }, String(rule.packets || 0)));
                    row.appendChild(E('td', { 'class': 'td' }, formatBytes(rule.bytes)));
                    row.appendChild(E('td', { 'class': 'td' },
                        E('code', { 'style': 'font-size: 11px; white-space: normal;' }, rule.raw || '')));
                    table.appendChild(row);
                });

                var ruleBody = E('div', { 'class': 'cbi-value-field' });
                if (data.parse_warning) {
                    ruleBody.appendChild(E('div', {
                        'style': 'color: orange; font-weight: bold; margin-bottom: 6px;'
                    }, data.parse_warning));
                } else if (data.rule_source === 'state') {
                    ruleBody.appendChild(E('div', {
                        'style': 'color: #777; margin-bottom: 6px;'
                    }, _('nft comments unavailable; showing the last verified agent rules with live counters.')));
                } else if (data.rule_source === 'nft_raw' || data.rule_source === 'nft_raw_state_mismatch') {
                    ruleBody.appendChild(E('div', {
                        'style': 'color: #777; margin-bottom: 6px;'
                    }, _('Showing live DSCP rules from nft while agent metadata catches up.')));
                }
                ruleBody.appendChild(table);

                panel.appendChild(E('div', { 'class': 'cbi-value' }, [
                    E('label', { 'class': 'cbi-value-title' },
                        _('Active Rules (%d)').format(data.rule_count || rules.length)),
                    ruleBody
                ]));

                return panel;
            }

            function renderAgentRpcError(err) {
                return E('div', { 'class': 'cbi-value' }, [
                    E('label', { 'class': 'cbi-value-title' }, _('Agent Status')),
                    E('div', { 'class': 'cbi-value-field' }, [
                        E('span', { 'style': 'color: red;' },
                            _('Failed to load agent status: %s').format(err && err.message ? err.message : err))
                    ])
                ]);
            }

            m = new form.Map('multiwan-qos', _('MultiWAN QoS PC Agent'),
                _('Allow a Windows PC agent to dynamically prioritize game traffic. ') +
                _('The agent detects running games, sets DSCP tags on Windows, and syncs active connections to this router in real-time.'));

            s = m.section(form.NamedSection, 'agent', 'agent', _('Agent Settings'));
            s.anonymous = true;

            o = s.option(form.Flag, 'enabled', _('Enable PC Agent Support'),
                _('When enabled, creates the API endpoint and a dedicated nftables chain for agent-reported game traffic. ') +
                _('Requires a MultiWAN QoS restart to take effect.'));
            o.rmempty = false;
            o.default = '0';

            o = s.option(form.Value, 'api_key', _('API Key'),
                _('Shared secret between the Windows agent and this router. ') +
                _('Paste this key into the Windows agent settings.'));
            o.password = true;
            o.rmempty = true;
            o.depends('enabled', '1');
            o.placeholder = _('Click Generate to create a key');

            o = s.option(form.Button, '_generate_key', _('Generate API Key'));
            o.inputstyle = 'apply';
            o.inputtitle = _('Generate New Key');
            o.depends('enabled', '1');
            o.onclick = ui.createHandlerFn(this, function () {
                var key = generateApiKey();
                var updated = setApiKeyValue(key);

                ui.addNotification(null, E('p', [
                    _('New API key generated. '),
                    updated
                        ? E('strong', _('Save & Apply to activate it, then copy it to your Windows agent.'))
                        : E('strong', _('The key was generated but the visible input could not be updated; reload this page if Save & Apply does not keep it.'))
                ]), updated ? 'info' : 'warning');
            });

            o = s.option(form.Button, '_copy_key', _('Copy API Key'));
            o.inputstyle = 'action';
            o.inputtitle = _('Copy to Clipboard');
            o.depends('enabled', '1');
            o.onclick = ui.createHandlerFn(this, function () {
                var key = getApiKeyValue();
                if (key) {
                    copyText(key).then(function () {
                        ui.addNotification(null, E('p', _('API key copied to clipboard.')), 'info');
                    }).catch(function () {
                        ui.addNotification(null, E('p', _('Failed to copy. Please copy manually.')), 'warning');
                    });
                } else {
                    ui.addNotification(null, E('p', _('No API key configured. Generate one first.')), 'warning');
                }
            });

            o = s.option(form.Value, 'timeout', _('Watchdog Timeout (seconds)'),
                _('If the Windows agent stops sending heartbeats for this long, all dynamic game rules are automatically cleared. ') +
                _('A supervised router check enforces this independently of the PC agent. Default: 120 seconds.'));
            o.datatype = 'uinteger';
            o.placeholder = '120';
            o.depends('enabled', '1');

            s = m.section(form.NamedSection, 'agent', 'agent', _('Agent Status'));
            s.anonymous = true;

            o = s.option(form.DummyValue, '_agent_status', _(''));
            o.rawhtml = true;
            o.depends('enabled', '1');
            o.render = function (section_id) {
                var container = E('div');

                function setAgentPollInterval(seconds) {
                    if (view.agentPollHandler && view.agentPollInterval === seconds)
                        return;

                    if (view.agentPollHandler)
                        poll.remove(view.agentPollHandler);

                    view.agentPollHandler = refreshRules;
                    view.agentPollInterval = seconds;
                    poll.add(view.agentPollHandler, seconds);
                }

                function refreshRules() {
                    var enabled = uci.get('multiwan-qos', 'agent', 'enabled');
                    if (enabled !== '1') {
                        setContent(container, renderAgentPanel({
                            enabled: false,
                            chain_exists: false,
                            pc_state: 'disabled',
                            rules: [],
                            rule_count: 0
                        }));
                        setAgentPollInterval(5);
                        return Promise.resolve();
                    }

                    return callAgentStatus()
                        .then(function (res) {
                            setContent(container, renderAgentPanel(res || {}));
                            setAgentPollInterval(shouldFastAgentPoll(res || {}) ? 2 : 5);
                        })
                        .catch(function (err) {
                            setContent(container, renderAgentRpcError(err));
                            setAgentPollInterval(5);
                        });
                }

                if (view.agentPollHandler)
                    poll.remove(view.agentPollHandler);
                view.agentPollHandler = null;
                view.agentPollInterval = null;
                setAgentPollInterval(5);
                refreshRules();

                return container;
            };

            return m.render();
        });
    }
});
