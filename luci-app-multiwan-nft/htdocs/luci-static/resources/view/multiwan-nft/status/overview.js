'use strict';
'require poll';
'require view';
'require rpc';

const callMwan3Status = rpc.declare({
	object: 'multiwan_nft',
	method: 'status',
	params: ['section'],
	expect: {  },
});

document.querySelector('head').appendChild(E('link', {
	'rel': 'stylesheet',
	'type': 'text/css',
	'href': L.resource('view/multiwan-nft/multiwan-nft.css')
}));

function renderMwan3Status(status) {
	if (!status.interfaces)
		return '<strong>%h</strong>'.format(_('No MultiWAN interfaces found'));

	var statusview = '';
	for ( var iface in status.interfaces) {
		var state = '';
		var css = '';
		var time = '';
		var tname = '';
		switch (status.interfaces[iface].status) {
			case 'online':
				state = _('Online');
				css = 'success';
				time = '%t'.format(status.interfaces[iface].online);
				tname = _('Uptime');
				css = 'success';
				break;
			case 'offline':
				state = _('Offline');
				css = 'danger';
				time = '%t'.format(status.interfaces[iface].offline);
				tname = _('Downtime');
				break;
			case 'waiting':
				state = _('Waiting for interface');
				css = 'warning';
				break;
			case 'notracking':
				state = _('No Tracking');
				if ((status.interfaces[iface].uptime) > 0) {
					css = 'success';
					time = '%t'.format(status.interfaces[iface].uptime);
					tname = _('Uptime');
				}
				else {
					css = 'warning';
					time = '';
					tname = '';
				}
				break;
			default:
				state = _('Disabled');
				css = 'warning';
				time = '';
				tname = '';
				break;
		}

		statusview += '<div class="alert-message %h">'.format(css);
		statusview += '<div><strong>%h:&#160;</strong>%h</div>'.format(_('Interface'), iface);
		statusview += '<div><strong>%h:&#160;</strong>%h</div>'.format(_('Status'), state);

		if (time)
			statusview += '<div><strong>%h:&#160;</strong>%h</div>'.format(tname, time);

		if (status.interfaces[iface].last_probe_result && status.interfaces[iface].last_probe_result != 'unknown')
			statusview += '<div><strong>%h:&#160;</strong>%h</div>'.format(_('Last probe result'), status.interfaces[iface].last_probe_result);
		if (status.interfaces[iface].offline_reason && status.interfaces[iface].offline_reason != 'none')
			statusview += '<div><strong>%h:&#160;</strong>%h</div>'.format(_('Offline reason'), status.interfaces[iface].offline_reason);
		if (status.interfaces[iface].policy_result && status.interfaces[iface].policy_result != 'unknown')
			statusview += '<div><strong>%h:&#160;</strong>%h</div>'.format(_('Policy update'), status.interfaces[iface].policy_result);
		if (status.interfaces[iface].recovery_rule_result && status.interfaces[iface].recovery_rule_result != 'unknown')
			statusview += '<div><strong>%h:&#160;</strong>%h</div>'.format(_('Recovery routing'), status.interfaces[iface].recovery_rule_result);
		if (status.interfaces[iface].sticky_result && status.interfaces[iface].sticky_result != 'unknown')
			statusview += '<div><strong>%h:&#160;</strong>%h (%d)</div>'.format(_('Sticky cleanup'), status.interfaces[iface].sticky_result, status.interfaces[iface].sticky_removed || 0);
		if (status.interfaces[iface].session_action && status.interfaces[iface].session_action != 'none')
			statusview += '<div><strong>%h:&#160;</strong>%h (%d)</div>'.format(_('Session action'), status.interfaces[iface].session_action, status.interfaces[iface].session_count || 0);

		statusview += '</div>';
	}

	return statusview;
}

return view.extend({
	load: function() {
		return Promise.all([
			callMwan3Status("interfaces"),
		]);
	},

	render: function (data) {
		poll.add(function() {
			return callMwan3Status("interfaces").then(function(result) {
				var view = document.getElementById('multiwan_nft-service-status');
				view.innerHTML = renderMwan3Status(result);
			});
		});

		return E('div', { class: 'cbi-map' }, [
			E('h2', [ _('MultiWAN Manager - Overview') ]),
			E('div', { class: 'cbi-section' }, [
				E('div', { 'id': 'multiwan_nft-service-status' }, [
					E('em', { 'class': 'spinning' }, [ _('Collecting data ...') ])
				])
			])
		]);
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
})
