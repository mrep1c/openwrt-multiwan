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
            'pfifo': ['PFIFOMIN']
        };
        
        // Settings that are used by multiple gameqdiscs
        var multiGameqdiscSettings = {
            'freshness_mode': ['red', 'pfifo', 'bfifo', 'fq_codel', 'drr', 'qfq', 'netem'],
            'freshness_target_ms': ['red', 'pfifo', 'bfifo', 'fq_codel', 'drr', 'qfq', 'netem'],
            'PACKETSIZE': ['red', 'pfifo', 'qfq', 'netem']
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
            var realtimeRateMode = uci.get('multiwan-qos', 'hfsc', 'realtime_rate_mode') || 'default';

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

        var realtimeFirstDescription = _('For HFSC and Hybrid in Default or Manual mode, place an ETS scheduler below the link shaper so EF, CS5, CS6, and CS7 are dequeued before non-realtime traffic. The selected game queue discipline remains unchanged. Continuously backlogged realtime traffic can delay or starve lower bands. Requires OpenWrt 24.10 or newer.');
        if (realtimeRateMode === 'adaptive')
            realtimeFirstDescription += ' ' + _('Currently unavailable because Adaptive takes precedence; the saved toggle value is preserved.');

        o = s.option(form.Flag, 'realtime_first_scheduling', _('Realtime First Scheduling'), realtimeFirstDescription);
        o.default = '0';
        o.rmempty = false;
        o.readonly = (realtimeRateMode === 'adaptive');

        o = s.option(form.ListValue, 'realtime_rate_mode', _('Realtime Rate Mode'),
            _('Default uses a fixed 1500 kbit/s reserve capped at 25% of the link. Manual uses the overrides below. Adaptive idles and starts new realtime sessions at the selected Adaptive Start / Idle Rate. While realtime packets are present, measured demand may adjust the HFSC rate from 300 to 1800 kbit/s, capped at 25% of the link. The first one-second sample without realtime traffic returns the rate to the selected baseline; the 20-second session grace tracks continuity only and cannot lower the rate. Increases use the highest one-second demand sample from the last 3 seconds plus the configured Adaptive Demand Reserve. Decreases use 30-second smoothed demand and 5-second burst memory, require clean drop and backlog history, and move in 50 kbit/s steps no faster than every 10 seconds. BFIFO and PFIFO use a fixed queue profile calculated at 1000 kbit/s; Adaptive changes only the HFSC class and never resizes the selected game qdisc.'));
        o.value('default', _('Default'));
        o.value('manual', _('Manual'));
        o.value('adaptive', _('Adaptive'));
        o.default = 'default';

        o = s.option(form.ListValue, 'adaptive_start_rate', _('Adaptive Start / Idle Rate'),
            _('Select the HFSC realtime baseline used when Adaptive starts and whenever realtime traffic becomes idle. The selected rate is capped at 25% of each link. It changes only the Adaptive HFSC rate and does not resize the fixed 1000 kbit/s BFIFO/PFIFO queue profile.'));
        o.value('1000', _('1000 kbit/s'));
        o.value('1500', _('1500 kbit/s'));
        o.default = '1000';
        o.rmempty = false;
        o.depends('realtime_rate_mode', 'adaptive');

        o = s.option(form.Value, 'adaptive_demand_reserve', _('Adaptive Demand Reserve (kbit/s)'),
            _('Fixed safety margin added to measured realtime demand when Adaptive calculates increases and decreases. It applies to both the 1000 and 1500 start/idle baselines. Higher values react with more spare capacity; lower values reserve less bandwidth. The final rate remains limited by the 1800 kbit/s Adaptive ceiling and the 25% link cap.'));
        o.default = '300';
        o.placeholder = '300';
        o.datatype = 'range(0, 1800)';
        o.rmempty = false;
        o.depends('realtime_rate_mode', 'adaptive');

        o = createOption('GAMEUP', _('Realtime Upload Reserve Override (kbit/s)'), _('Manual upload reserve. A blank value keeps the default reserve for this direction.'), _('Default: fixed 1500 kbit/s'), 'uinteger');
        o.depends('realtime_rate_mode', 'manual');
        o = createOption('GAMEDOWN', _('Realtime Download Reserve Override (kbit/s)'), _('Manual download reserve. A blank value keeps the default reserve for this direction.'), _('Default: fixed 1500 kbit/s'), 'uinteger');
        o.depends('realtime_rate_mode', 'manual');

        o = s.option(form.ListValue, 'nongameqdisc', _('Non-Game Queue Discipline'), 
            addRelevanceInfo(_('Select the queueing discipline for non-realtime traffic'), 'nongameqdisc', rootQdisc, gameqdisc));
        o.value('fq_codel', _('FQ_CODEL'));
        o.value('cake', _('CAKE'));
        o.default = 'fq_codel';

        createOption('nongameqdiscoptions', _('Non-Game QDisc Options'), _('Cake options for non-realtime queueing discipline'), _('Default: besteffort ack-filter'));

        o = s.option(form.ListValue, 'freshness_mode', _('Realtime Freshness'),
            addRelevanceInfo(_('Finite realtime queue budget. Auto/Balanced: 18 ms, Tight: 14 ms, Relaxed: 22 ms, Custom: use the custom target below. Queue capacity uses the detected MTU as its minimum; the HFSC burst segment remains fixed at 25 ms and game FQ_CODEL keeps its independent 5 ms target.'), 'freshness_mode', rootQdisc, gameqdisc));
        o.value('auto', _('Auto (Balanced)'));
        o.value('tight', _('Tight'));
        o.value('balanced', _('Balanced'));
        o.value('relaxed', _('Relaxed'));
        o.value('custom', _('Custom'));
        o.default = 'auto';

        o = createOption('freshness_target_ms', _('Custom Freshness Target (ms)'), _('Manual finite realtime queue target. The HFSC burst remains 25 ms and game FQ_CODEL keeps its independent 5 ms target.'), _('Default: 18'), 'uinteger');
        o.depends('freshness_mode', 'custom');

        o = createOption('PFIFOMIN', _('PFIFO Min'), _('Minimum packet count for PFIFO queue'), _('Default: 5'), 'uinteger');
        o.depends('gameqdisc', 'pfifo');

        o = createOption('PACKETSIZE', _('Avg Packet Size (B)'), _('Used to convert byte budgets for PFIFO, RED, NETEM, and QFQ child queues. Default: 450 bytes.'), _('Default: 450'), 'uinteger');
        o.depends('gameqdisc', 'pfifo');
        o.depends('gameqdisc', 'red');
        o.depends('gameqdisc', 'netem');
        o.depends('gameqdisc', 'qfq');

        o = createOption('netemdelayms', _('NETEM Delay (ms)'), _('NETEM delay in milliseconds'), _('Default: 30'), 'uinteger');
        o.depends('gameqdisc', 'netem');
        o = createOption('netemjitterms', _('NETEM Jitter (ms)'), _('NETEM jitter in milliseconds'), _('Default: 7'), 'uinteger');
        o.depends('gameqdisc', 'netem');

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
        o.depends('gameqdisc', 'netem');

        o = createOption('pktlossp', _('Packet Loss Percentage'), _('Percentage of packet loss'), _('Default: none'));
        o.depends('gameqdisc', 'netem');

        return m.render();
        });
    }
});
