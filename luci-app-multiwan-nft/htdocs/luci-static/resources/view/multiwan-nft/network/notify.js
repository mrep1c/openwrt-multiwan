'use strict';
'require view';
'require fs';
'require ui';

var isReadonlyView = !L.hasViewPermission() || null;
var MAX_USER_SCRIPT_BYTES = 64 * 1024;

return view.extend({
	load: function() {
		return L.resolveDefault(fs.read('/etc/multiwan-nft.user'), '');
	},

	handleSave: function(ev) {
		var value = (document.querySelector('textarea').value || '').trim().replace(/\r\n/g, '\n') + '\n';
		var size = new Blob([ value ]).size;

		if (size > MAX_USER_SCRIPT_BYTES) {
			ui.addNotification(null, E('p', _('Unable to save contents: file is %d bytes; maximum is %d bytes.').format(size, MAX_USER_SCRIPT_BYTES)), 'error');
			return Promise.resolve();
		}

		return fs.write('/etc/multiwan-nft.user', value).then(function(rc) {
			document.querySelector('textarea').value = value;
				ui.addNotification(null, E('p', _('Contents have been saved.')), 'info');
			}).catch(function(e) {
				ui.addNotification(null, E('p', _('Unable to save contents: %s').format(e.message)));
			});
		},

	render: function(multiwan_nftuser) {
		return E([
			E('h2', _('MultiWAN Manager - Notify')),
			E('p', { 'class': 'cbi-section-descr' },
			_('This section allows you to modify the content of \"/etc/multiwan-nft.user\".') + '<br/>' +
			_('The file is also preserved during sysupgrade.') + '<br/>' +
			'<br />' +
			_('Notes:') + '<br />' +
			_('This file is interpreted as a shell script.') + '<br />' +
			_('The first line of the script must be &#34;#!/bin/sh&#34; without quotes.') + '<br />' +
			_('Lines beginning with # are comments and are not executed.') + '<br />' +
			_('Put your custom multiwan_nft action here, they will be executed with each netifd hotplug interface event on interfaces for which multiwan_nft is enabled.') + '<br />' +
			'<br />' +
			_('There are three main environment variables that are passed to this script.') + '<br />' +
			'<br />' +
			_('%s: Name of the action that triggered this event').format('$ACTION') + '<br />' +
			_('* %s: Is called by netifd and multiwan-nft-track').format('ifup') + '<br />' +
			_('* %s: Is called by netifd and multiwan-nft-track').format('ifdown') + '<br />' +
			_('* %s: Is only called by multiwan-nft-track if tracking was successful').format('connected') + '<br />' +
			_('* %s: Is only called by multiwan-nft-track if tracking has failed').format('disconnected') + '<br />' +
			_('%s: Name of the interface which went up or down (e.g. \"wan\" or \"wwan\")').format('$INTERFACE') + '<br />' +
			_('%s: Name of Physical device which interface went up or down (e.g. \"eth0\" or \"wwan0\")').format('$DEVICE') + '<br />'),
			E('p', {}, E('textarea', { 'style': 'width:100%', 'rows': 10, 'disabled': isReadonlyView }, [ multiwan_nftuser != null ? multiwan_nftuser : '' ]))
		]);
	},

	handleSaveApply: null,
	handleReset: null
});
