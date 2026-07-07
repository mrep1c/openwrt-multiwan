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
function addRelevanceInfo(description, settingName, rootQdisc, gameqdisc) {
    var isRelevant = true;
    var note = '';
    
    // Check per-interface qdisc relevance
    if (rootQdisc !== 'hfsc' && rootQdisc !== 'hybrid') {
        isRelevant = false;
        note = ' [inactive: ' + rootQdisc.toUpperCase() + ' mode]';
    } else {
        // Check gameqdisc-specific dependencies
        var gameqdiscDependencies = {
            'netem': ['netemdelayms', 'netemjitterms', 'netemdist', 'netem_direction', 'pktlossp'],
            'pfifo': ['PFIFOMIN', 'PACKETSIZE'], // PFIFO-specific settings
            // MAXDEL is used by multiple qdiscs, so handle separately
        };
        
        // Settings that are used by multiple gameqdiscs
        var multiGameqdiscSettings = {
            'MAXDEL': ['red', 'pfifo', 'bfifo', 'qfq'] // Used for burst/limit calculations
        };
        
        // Check if setting is gameqdisc-specific
        var isGameqdiscSpecific = false;
        var requiredGameqdisc = '';
        var supportedGameqdiscs = [];
        
        // Check single-gameqdisc dependencies
        for (var qdisc in gameqdiscDependencies) {
            if (gameqdiscDependencies[qdisc].includes(settingName)) {
                isGameqdiscSpecific = true;
                if (qdisc !== gameqdisc) {
                    isRelevant = false;
                    requiredGameqdisc = qdisc;
                }
                break;
            }
        }
        
        // Check multi-gameqdisc settings
        if (!isGameqdiscSpecific && multiGameqdiscSettings[settingName]) {
            supportedGameqdiscs = multiGameqdiscSettings[settingName];
            isGameqdiscSpecific = true;
            if (!supportedGameqdiscs.includes(gameqdisc)) {
                isRelevant = false;
            }
        }
        
        // Check hybrid-specific settings
        if (rootQdisc === 'hybrid') {
            if (settingName === 'nongameqdisc' || settingName === 'nongameqdiscoptions') {
                isRelevant = false;
                note = ' [hybrid uses CAKE for default traffic and fq_codel for bulk]';
            }
        }
        
        // Generate appropriate note
        if (isRelevant) {
            if (isGameqdiscSpecific) {
                note = ' [active: ' + rootQdisc.toUpperCase() + ' + ' + gameqdisc.toUpperCase() + ']';
            } else {
                note = ' [active: ' + rootQdisc.toUpperCase() + ']';
            }
        } else {
            if (requiredGameqdisc) {
                note = ' [only relevant for ' + requiredGameqdisc.toUpperCase() + ' gameqdisc]';
            } else if (supportedGameqdiscs.length > 0) {
                var gameqdiscList = supportedGameqdiscs.map(function(q) { return q.toUpperCase(); }).join(', ');
                note = ' [only relevant for ' + gameqdiscList + ' gameqdisc' + (supportedGameqdiscs.length > 1 ? 's' : '') + ']';
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
            var gameqdisc = uci.get('multiwan-qos', 'hfsc', 'gameqdisc') || 'pfifo';

            var relevanceText = '';
            if (rootQdisc === 'hfsc') {
                relevanceText = _('HFSC mode active.');
            } else if (rootQdisc === 'hybrid') {
                relevanceText = _('Hybrid mode active - realtime/default/bulk lanes only.');
            } else {
                relevanceText = _('Current queue discipline is %s - HFSC settings are not used.').format(rootQdisc.toUpperCase());
            }

            m = new form.Map('multiwan-qos', _('MultiWAN QoS HFSC Settings'), _('Configure HFSC settings for MultiWAN QoS.') + ' ' + relevanceText);

            s = m.section(form.NamedSection, 'hfsc', 'hfsc', _('HFSC Settings'));
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
            opt.description = addRelevanceInfo(description, name, rootQdisc, gameqdisc);
            
            return opt;
        }

        o = s.option(form.ListValue, 'gameqdisc', _('Game Queue Discipline'), 
            addRelevanceInfo(_('Queueing method for traffic classified as realtime'), 'gameqdisc', rootQdisc, gameqdisc));
        o.value('pfifo', _('PFIFO'));
        o.value('fq_codel', _('FQ_CODEL'));
        o.value('bfifo', _('BFIFO'));
        o.value('red', _('RED'));
        o.value('drr', _('DRR'));
        o.value('netem', _('NETEM'));
        o.default = 'pfifo';

        createOption('GAMEUP', _('Realtime Upload Reserve Override (kbit/s)'), _('Optional bandwidth override for the realtime/game upload lane. Leave empty for auto 1500 kbit/s, capped at 25% of very slow links. Increase only if realtime drops persist; use the stale-packet budget for freshness.'), _('Default: auto'), 'uinteger');
        createOption('GAMEDOWN', _('Realtime Download Reserve Override (kbit/s)'), _('Optional bandwidth override for the realtime/game download lane. Leave empty for auto 1500 kbit/s, capped at 25% of very slow links. Increase only if realtime drops persist; use the stale-packet budget for freshness.'), _('Default: auto'), 'uinteger');

        o = s.option(form.ListValue, 'nongameqdisc', _('Non-Game Queue Discipline'), 
            addRelevanceInfo(_('Select the queueing discipline for non-realtime traffic'), 'nongameqdisc', rootQdisc, gameqdisc));
        o.value('fq_codel', _('FQ_CODEL'));
        o.value('cake', _('CAKE'));
        o.default = 'fq_codel';

        createOption('nongameqdiscoptions', _('Non-Game QDisc Options'), _('Cake options for non-realtime queueing discipline'), _('Default: besteffort ack-filter'));
        createOption('MAXDEL', _('Realtime Stale Packet Budget (ms)'), _('Delay budget for finite realtime queues. Lower values drop stale packets sooner and can feel sharper; higher values tolerate bursty marking. Try 16 ms for sharp, 20 ms for balanced, or 24 ms for safer burst handling.'), _('Default: 24'), 'uinteger');
        createOption('PFIFOMIN', _('PFIFO Min'), _('Minimum packet count for PFIFO queue'), _('Default: 5'), 'uinteger');
        createOption('PACKETSIZE', _('Avg Packet Size (B)'), _('Used with PFIFOMIN to calculate PFIFO limit'), _('Default: 450'), 'uinteger');
        createOption('netemdelayms', _('NETEM Delay (ms)'), _('NETEM delay in milliseconds'), _('Default: 30'), 'uinteger');
        createOption('netemjitterms', _('NETEM Jitter (ms)'), _('NETEM jitter in milliseconds'), _('Default: 7'), 'uinteger');

        o = s.option(form.ListValue, 'netem_direction', _('NETEM Direction'), 
            addRelevanceInfo(_('Select which direction to apply the NETEM delay/jitter settings'), 'netem_direction', rootQdisc, gameqdisc));
        o.depends('gameqdisc', 'netem');
        o.value('both', _('Both Directions'));
        o.value('egress', _('Egress Only'));
        o.value('ingress', _('Ingress Only'));
        o.default = 'both';
        
        o = s.option(form.ListValue, 'netemdist', _('NETEM Distribution'), 
            addRelevanceInfo(_('NETEM delay distribution'), 'netemdist', rootQdisc, gameqdisc));
        o.value('experimental', _('Experimental'));
        o.value('normal', _('Normal'));
        o.value('pareto', _('Pareto'));
        o.value('paretonormal', _('Pareto Normal'));
        o.default = 'normal';

        createOption('pktlossp', _('Packet Loss Percentage'), _('Percentage of packet loss'), _('Default: none'));

        return m.render();
        });
    }
});
