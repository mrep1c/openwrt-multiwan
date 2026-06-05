'use strict';
'require form';
'require view';

return view.extend({

	render: function () {
		let m, s, o;

		m = new form.Map('multiwan-nft', _('MultiWAN Manager - Globals'));

		s = m.section(form.NamedSection, 'globals', 'globals');

		o = s.option(form.Value, 'mmx_mask', _('Firewall mask'),
			_('Hex routing mark mask. Use at least three bits and avoid the lower byte, which is reserved for MultiWAN QoS.'));
		o.default = '0x3F0000';
		o.placeholder = '0x3F0000';
		o.validate = function (section_id, value) {
			var mask, bits = 0;

			value = String(value || '').trim();
			if (!/^0x[0-9a-fA-F]{1,8}$/.test(value))
				return _('Use a hexadecimal value starting with 0x, for example 0x3F0000.');

			mask = parseInt(value.substring(2), 16) >>> 0;
			if ((mask & 0x000000ff) !== 0)
				return _('The lower 8 bits are reserved for MultiWAN QoS. Use a mask such as 0x3F0000 or 0x00FC0000.');

			while (mask) {
				bits += mask & 1;
				mask >>>= 1;
			}

			if (bits < 3)
				return _('Set at least three mask bits.');

			return true;
		};

		o = s.option(form.Flag, 'logging', _('Logging'),
			_('Enables global firewall logging'));

		o = s.option(form.ListValue, 'loglevel', _('Loglevel'),
			_('Firewall loglevel'));
		o.default = 'notice';
		o.value('emerg', _('Emergency'));
		o.value('alert', _('Alert'));
		o.value('crit', _('Critical'));
		o.value('error', _('Error'));
		o.value('warning', _('Warning'));
		o.value('notice', _('Notice'));
		o.value('info', _('Info'));
		o.value('debug', _('Debug'));
		o.depends('logging', '1');

		o = s.option(form.DynamicList, 'rt_table_lookup',
			_('Routing table lookup'),
			_('Also scan this Routing table for connected networks'));
		o.datatype = 'uinteger';
		o.value('220', _('Routing table %d').format('220'));

		return m.render();
	}
})
