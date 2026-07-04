'use strict';
'require view';
'require form';
'require ui';
'require uci';
'require rpc';
'require fs';

function getPrimaryInterfaceQdisc() {
    var qdisc = 'hfsc';

    uci.sections('multiwan-qos', 'interface', function(s) {
        if (s.enabled === '0')
            return;

        qdisc = s.qdisc || 'hfsc';
        return false;
    });

    return qdisc;
}

// Helper function to add relevance info to descriptions  
function addRelevanceInfo(description, settingName, rootQdisc) {
    var isRelevant = true;
    var note = '';
    
    // Check per-interface qdisc relevance
    if (rootQdisc !== 'cake' && rootQdisc !== 'hybrid') {
        isRelevant = false;
        note = ' [inactive: ' + rootQdisc.toUpperCase() + ' mode]';
    } else {
        // Check hybrid-specific restrictions
        if (rootQdisc === 'hybrid') {
            if (settingName === 'PRIORITY_QUEUE_INGRESS' || settingName === 'PRIORITY_QUEUE_EGRESS') {
                isRelevant = false;
                note = ' [hybrid default lane uses besteffort, no priority queues]';
            } else if (settingName === 'AUTORATE_INGRESS') {
                isRelevant = false;
                note = ' [hybrid default lane uses besteffort, no autorate]';
            } else if (settingName === 'USE_MQ') {
                isRelevant = false;
                note = ' [hybrid default lane uses plain CAKE child qdisc]';
            }
        }
        
        // Generate appropriate note
        if (isRelevant) {
            if (rootQdisc === 'hybrid') {
                note = ' [active: ' + rootQdisc.toUpperCase() + ' default traffic lane]';
            } else {
                note = ' [active: ' + rootQdisc.toUpperCase() + ']';
            }
        }
    }
    
    return description + note;
}

var callInitAction = rpc.declare({
    object: 'luci',
    method: 'setInitAction',
    params: ['name', 'action'],
    expect: { result: false }
});

return view.extend({
    handleSaveApply: function(ev) {
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

    render: function() {
        return Promise.all([
            uci.load('multiwan-qos')
        ]).then(() => {
            var m, s, o;
            var rootQdisc = getPrimaryInterfaceQdisc();

            var relevanceText = '';
            if (rootQdisc === 'cake') {
                relevanceText = _('CAKE mode active.');
            } else if (rootQdisc === 'hybrid') {
                relevanceText = _('Hybrid mode active - these settings control the default lane only.');
            } else {
                relevanceText = _('Current queue discipline is %s - CAKE settings are not used.').format(rootQdisc.toUpperCase());
            }

            m = new form.Map('multiwan-qos', _('MultiWAN QoS CAKE Settings'), _('Configure CAKE settings for MultiWAN QoS.') + ' ' + relevanceText);

            s = m.section(form.NamedSection, 'cake', 'cake', _('CAKE Settings'));
            s.anonymous = true;

        function createOption(name, title, description, placeholder, datatype) {
            var opt = s.option(form.Value, name, title, description);
            opt.datatype = datatype || 'string';
            opt.rmempty = true;
            opt.placeholder = placeholder;
            
            if (datatype === 'uinteger') {
                opt.validate = function(section_id, value) {
                    if (value === '' || value === null) return true;
                    if (!/^\d+$/.test(value)) return _('Must be a non-negative integer or empty');
                    return true;
                };
            }
            
            // Add relevance info to description
            opt.description = addRelevanceInfo(description, name, rootQdisc);
            
            return opt;
        }
        
        o = s.option(form.ListValue, 'PRIORITY_QUEUE_INGRESS', _('Priority Queue (Ingress)'), 
            addRelevanceInfo(_('Sets CAKE\'s diffserv mode for incoming traffic'), 'PRIORITY_QUEUE_INGRESS', rootQdisc));
        o.value('diffserv3', _('Diffserv 3-tier priority'));
        o.value('diffserv4', _('Diffserv 4-tier priority'));
        o.value('diffserv8', _('Diffserv 8-tier priority'));
        o.default = 'diffserv4';

        o = s.option(form.ListValue, 'PRIORITY_QUEUE_EGRESS', _('Priority Queue (Egress)'), 
            addRelevanceInfo(_('Sets CAKE\'s diffserv mode for outgoing traffic'), 'PRIORITY_QUEUE_EGRESS', rootQdisc));
        o.value('diffserv3', _('Diffserv 3-tier priority'));
        o.value('diffserv4', _('Diffserv 4-tier priority'));
        o.value('diffserv8', _('Diffserv 8-tier priority'));
        o.default = 'diffserv4';

        o = s.option(form.Flag, 'HOST_ISOLATION', _('Host Isolation'), 
            addRelevanceInfo(_('Applies fairness first by host, then by flow(dual-srchost/dual-dsthost)'), 'HOST_ISOLATION', rootQdisc));
        o.rmempty = false;
        o.default = '1';

        o = s.option(form.Flag, 'NAT_INGRESS', _('NAT (Ingress)'), 
            addRelevanceInfo(_('Enable NAT lookup for ingress'), 'NAT_INGRESS', rootQdisc));
        o.rmempty = false;
        o.default = '1';

        o = s.option(form.Flag, 'NAT_EGRESS', _('NAT (Egress)'), 
            addRelevanceInfo(_('Enable NAT lookup for egress'), 'NAT_EGRESS', rootQdisc));
        o.rmempty = false;
        o.default = '1';

        o = s.option(form.ListValue, 'ACK_FILTER_EGRESS', _('ACK Filter (Egress)'), 
            addRelevanceInfo(_('Set ACK filter for egress. Auto enables filtering if download/upload ratio ≥ 15.'), 'ACK_FILTER_EGRESS', rootQdisc));
        o.value('auto', _('Auto'));
        o.value('1', _('Enable'));
        o.value('0', _('Disable'));
        o.default = 'auto';

        o = s.option(form.Flag, 'USE_MQ', _('Multi-Queue CAKE (cake_mq)'),
            addRelevanceInfo(_('Use cake_mq for pure CAKE on multi-queue devices when kernel support is available'), 'USE_MQ', rootQdisc));
        o.rmempty = false;
        o.default = '0';

        createOption('RTT', _('RTT'), _('Set the Round Trip Time'), _('Default: auto'), 'uinteger');

        o = s.option(form.Flag, 'AUTORATE_INGRESS', _('CAKE Ingress Autorate'),
            addRelevanceInfo(_('Enable CAKE built-in autorate-ingress for the download qdisc'), 'AUTORATE_INGRESS', rootQdisc));
        o.rmempty = false;
        o.default = '0';

        createOption('EXTRA_PARAMETERS_INGRESS', _('Extra Parameters (Ingress)'), _('Set extra parameters for ingress'), _('Default: none'));
        createOption('EXTRA_PARAMETERS_EGRESS', _('Extra Parameters (Egress)'), _('Set extra parameters for egress'), _('Default: none'));

        return m.render();
        });
    }
});
