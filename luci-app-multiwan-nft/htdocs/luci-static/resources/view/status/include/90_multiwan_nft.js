'use strict';
'require baseclass';
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

return baseclass.extend({
	title: _('MultiWAN Manager'),

	load: function() {
		return Promise.all([
			callMwan3Status("interfaces"),
		]);
	},

	render: function (result) {
		var container = E('div', { 'id': 'multiwan_nft-service-status' });
		if (result[0].reconfiguration_pending)
			container.appendChild(E('div', { 'class': 'alert-message warning' }, [ _('Routing configuration is incomplete. Affected connections remain blocked. Check the system log if this persists.') ]));
		if (result[0].running === false) {
			container.appendChild(E('div', { 'class': 'alert-message warning' }, [ _('MultiWAN routing is stopped.') ]));
			return container;
		}
		if (!result[0].interfaces)
			return result[0].reconfiguration_pending ? container : null;

		var iface;
		for ( iface in result[0].interfaces) {
			var state = '';
			var css = '';
			var time = '';
			var tname = '';
			switch (result[0].interfaces[iface].status) {
				case 'online':
					state = _('Online');
					css = 'alert-message success';
					time = '%t'.format(result[0].interfaces[iface].online);
					tname = _('Uptime');
					break;
				case 'offline':
					state = _('Offline');
					css = 'alert-message danger';
					time = '%t'.format(result[0].interfaces[iface].offline);
					tname = _('Downtime');
					break;
				case 'notracking':
					state = _('No Tracking');
					if ((result[0].interfaces[iface].uptime) > 0) {
						css = 'alert-message success';
						time = '%t'.format(result[0].interfaces[iface].uptime);
						tname = _('Uptime');
					}
					else {
						css = 'alert-message warning';
						time = '';
						tname = '';
					}
					break;
				case 'waiting':
					state = _('Waiting for interface');
					css = 'alert-message warning';
					break;
				case 'connecting':
					state = _('Connecting');
					css = 'alert-message warning';
					break;
				case 'disconnecting':
					state = _('Disconnecting');
					css = 'alert-message warning';
					break;
				case 'disabled':
					css = 'alert-message warning';
					state = _('Disabled');
					break;
				default:
					css = 'alert-message warning';
					state = _('Unknown');
					break;
			}

			if (time !== '' ) {
				container.appendChild(
					E('div', { 'class': css }, [
						E('div', {}, [
							E('strong', {}, [
								_('Interface'), ':', ' '
							]),
							iface
						]),
						E('div', {}, [
							E('strong', {}, [
								_('Status'), ':', ' '
							]),
							state
						]),
						E('div', {}, [
							E('strong', {}, [
								tname, ':', ' '
							]),
							time
						])
					])
				);
			}
			else {
				container.appendChild(
					E('div', { 'class': css }, [
						E('div', {}, [
							E('strong', {}, [
								_('Interface'), ':', ' '
							]),
							iface
						]),
						E('div', {}, [
							E('strong', {}, [
								_('Status'), ':', ' '
							]),
							state
						])
					])
				);
			}
		}

		return container;
	}
});
