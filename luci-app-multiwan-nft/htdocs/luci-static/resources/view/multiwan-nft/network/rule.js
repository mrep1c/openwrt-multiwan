'use strict';
'require form';
'require fs';
'require view';
'require uci';
'require ui';

return view.extend({
	load: function () {
		return Promise.all([
			fs.exec_direct('/usr/libexec/luci-multiwan-nft', ['ipset', 'dump']),
			uci.load('multiwan-nft')
		]);
	},

	render: function (data) {
		let m, s, o;

		m = new form.Map('multiwan-nft', _('MultiWAN Manager - Rules'),
			_('Rules specify which traffic will use a particular MultiWAN policy.') + '<br />' +
			_('Rules are based on IP address, port or protocol.') + '<br />' +
			_('Rules are matched from top to bottom.') + '<br />' +
			_('Rules below a matching rule are ignored.') + '<br />' +
			_('Traffic not matching any rule is routed using the main routing table.') + '<br />' +
			_('Traffic destined for known (other than default) networks is handled by the main routing table.') + '<br />' +
			_('Traffic matching a rule, but all WAN interfaces for that policy are down will be blackholed.') + '<br />' +
			_('Names may contain characters A-Z, a-z, 0-9, _ and no spaces.') + '<br />' +
			_('Rules may not share the same name as configured interfaces, members or policies.'));

		s = m.section(form.GridSection, 'rule');
		s.addremove = true;
		s.anonymous = false;
		s.nodescriptions = true;
		s.sortable = true;

		/* Keep names within legacy-compatible lengths used by migrated configs. */
		s.renderSectionAdd = function (extra_class) {
			var el = form.GridSection.prototype.renderSectionAdd.apply(this, arguments),
				nameEl = el.querySelector('.cbi-section-create-name');
			ui.addValidator(nameEl, 'uciname', true, function (v) {
				let sections = [
					...uci.sections('multiwan-nft', 'interface'),
					...uci.sections('multiwan-nft', 'member'),
					...uci.sections('multiwan-nft', 'policy'),
					...uci.sections('multiwan-nft', 'rule')
				];

				for (let j = 0; j < sections.length; j++) {
					if (sections[j]['.name'] == v) {
						return _('Rules may not share the same name as configured interfaces, members or policies.');
					}
				}
				return true;
			}, 'blur', 'keyup');
			return el;
		};

		o = s.option(form.ListValue, 'family', _('Internet Protocol'));
		o.default = '';
		o.value('', _('IPv4 and IPv6'));
		o.value('ipv4', _('IPv4 only'));
		o.value('ipv6', _('IPv6 only'));
		o.modalonly = true;

		o = s.option(form.Value, 'proto', _('Protocol'),
			_('View the content of /etc/protocols for protocol description'));
		o.default = 'all';
		o.rmempty = false;
		o.value('all');
		o.value('tcp');
		o.value('udp');
		o.value('icmp');
		o.value('esp');

		o = s.option(form.Value, 'src_ip', _('Source address'),
			_('Supports CIDR notation (eg \"192.168.100.0/24\") without quotes'));
		o.datatype = 'ipaddr';

		o = s.option(form.Value, 'src_port', _('Source port'),
			_('May be entered as a single or multiple port(s) (eg \"22\" or \"80,443\") or as a portrange (eg \"1024:2048\") without quotes'));
		o.depends('proto', 'tcp');
		o.depends('proto', 'udp');

		o = s.option(form.Value, 'dest_ip', _('Destination address'),
			_('Supports CIDR notation (eg \"192.168.100.0/24\") without quotes'));
		o.datatype = 'ipaddr';

		o = s.option(form.Value, 'dest_port', _('Destination port'),
			_('May be entered as a single or multiple port(s) (eg \"22\" or \"80,443\") or as a portrange (eg \"1024:2048\") without quotes'));
		o.depends('proto', 'tcp');
		o.depends('proto', 'udp');

		o = s.option(form.ListValue, 'sticky', _('Sticky'),
			_('Traffic from the same source IP address that previously matched this rule within the sticky timeout period will use the same WAN interface'));
		o.default = '0';
		o.value('1', _('Yes'));
		o.value('0', _('No'));
		o.modalonly = true;

		o = s.option(form.Value, 'timeout', _('Sticky timeout'),
			_('Seconds. Acceptable values: 1-1000000. Defaults to 600 if not set'));
		o.datatype = 'range(1, 1000000)';
		o.modalonly = true;
		o.depends('sticky', '1');

		o = s.option(form.Value, 'ipset', _('NFT set'),
			_('Address set in table inet multiwan_nft. Missing sets are created from this rule family (Any defaults to IPv4). For dnsmasq-full use nftset=/youtube.com/4#inet#multiwan_nft#youtube for set youtube; use 6# and an IPv6 rule for IPv6. Sets survive service restarts.'));
		o.validate = function(section_id, value) {
			return !value || (/^[a-zA-Z0-9_.-]+$/.test(value) && !/^multiwan_nft_/.test(value)) ||
				_('Use letters, digits, dots, hyphens or underscores; multiwan_nft_ names are reserved.');
		};
		o.value('', _('-- Please choose --'));
		var ipsets = data[0].split(/\n/);
		for (var i = 0; i < ipsets.length; i++) {
			if (ipsets[i].length > 0)
				o.value(ipsets[i]);
		}
		o.modalonly = true;

		o = s.option(form.Flag, 'logging', _('Logging'),
			_('Enables firewall rule logging (global multiwan_nft logging must also be enabled)'));
		o.modalonly = true;

		o = s.option(form.ListValue, 'use_policy', _('Policy assigned'));
		var options = uci.sections('multiwan-nft', 'policy')
		for (var i = 0; i < options.length; i++) {
			var value = options[i]['.name'];
			o.value(value);
		}
		o.value('unreachable', _('unreachable (reject)'));
		o.value('blackhole', _('blackhole (drop)'));
		o.value('default', _('default (use main routing table)'));

		return m.render();
	}
})
