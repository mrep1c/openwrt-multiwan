'use strict';
'require fs';
'require view';

return view.extend({
	load: function () {
		return Promise.all([
			L.resolveDefault(fs.exec_direct('/usr/sbin/multiwan-nft', ['internal', 'ipv4']), ''),
			L.resolveDefault(fs.exec_direct('/usr/sbin/multiwan-nft', ['internal', 'ipv6']), '')
		]);
	},

	render: function (data) {
		var ipv4_report = data[0] || '';
		var ipv6_report = data[1] || '';

		return E('div', { 'class': 'cbi-map', 'id': 'map' }, [
			E('h2', _('MultiWAN Manager - Troubleshooting')),
			E('div', { 'class': 'cbi-section' }, [
				E('h3', _('IPv4')),
				E('pre', [ipv4_report]),
				E('h3', _('IPv6')),
				E('pre', [ipv6_report])
			]),
		])
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
})
