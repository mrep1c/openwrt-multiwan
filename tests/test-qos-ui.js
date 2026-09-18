'use strict';

// Run the shipped view with only LuCI's form registration mocked.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const uiDir = path.join(__dirname, '../luci-app-multiwan-qos/htdocs/luci-static/resources/multiwan-qos');
const options = {};
const fields = { enabled: '1', qdisc: 'hfsc', upload: '10000', download: '20000' };
let rateMode = 'manual';
const section = {
    option(type, name) {
        const option = { option: name, section: this, value() {} };
        options[name] = option;
        return option;
    },
    formvalue(id, name) { return fields[name]; }
};
const context = vm.createContext({
    view: { extend: value => value },
    rpc: { declare: () => () => {} },
    ui: { createHandlerFn() {} },
    uci: { get: () => rateMode },
    widgets: {},
    form: { Map: function () { this.section = () => section; this.render = () => {}; } },
    _: value => value
});
vm.runInContext('String.prototype.format = function (...args) { let i = 0; return this.replace(/%[sd]/g, () => args[i++]); };', context);
const settings = vm.runInContext('(function () {\n' + fs.readFileSync(path.join(uiDir, 'settings.js'), 'utf8') + '\n})()', context);
settings.render();

function accepted(option, value) {
    return !options[option].validate || options[option].validate('wan', value) === true;
}

for (const [option, direction] of [['game_up', 'upload'], ['game_down', 'download']]) {
    for (const value of ['0', fields[direction], '999999', '-1', '1.5', 'abc'])
        assert.equal(accepted(option, value), false, `${option} accepted invalid reserve ${value}`);
    for (const value of ['', null, '1', String(Number(fields[direction]) - 1)])
        assert.equal(accepted(option, value), true, `${option} rejected reserve ${value}`);

    // A bandwidth edit must be checked before it has been saved to UCI.
    fields[direction] = '1500';
    assert.equal(accepted(option, '2000'), false, `${option} ignored edited bandwidth`);
    fields[direction] = '3000000';
    assert.equal(accepted(option, '2500000'), false, `${option} ignored backend maximum rate`);
    fields[direction] = '500';
    assert.equal(accepted(option, '999'), true, `${option} ignored backend minimum rate`);
    assert.equal(accepted(option, '1000'), false);
    fields[direction] = '10000';
}

fields.qdisc = 'hybrid';
assert.equal(accepted('game_down', '10000'), false);
for (const qdisc of ['cake', 'htb']) {
    fields.qdisc = qdisc;
    assert.equal(accepted('game_up', '999999'), true, `${qdisc} rejected an unused reserve`);
}
fields.qdisc = 'hfsc';
for (const mode of ['default', 'adaptive']) {
    rateMode = mode;
    assert.equal(accepted('game_up', '999999'), true, `${mode} rejected an unused reserve`);
}
rateMode = 'manual';
fields.enabled = '0';
assert.equal(accepted('game_up', '999999'), true, 'disabled interface rejected an unused reserve');

// Exercise the shipped warning callback without constructing the connection table.
context.limitWarning = { style: {}, textContent: '' };
const connections = fs.readFileSync(path.join(uiDir, 'connections.js'), 'utf8');
const warning = connections.match(/view\.updateLimitWarning = function \(status\) \{[\s\S]*?\n        \};/);
assert.ok(warning, 'connection limit warning callback missing');
vm.runInContext(warning[0], context);
context.view.updateLimitWarning({ max_connections: 0, effective_max_connections: 100, truncated: true });
assert.equal(context.limitWarning.style.display, 'block', 'automatic truncation warning hidden');
assert.match(context.limitWarning.textContent, /100 connections/);
assert.match(context.limitWarning.textContent, /larger flows/);
context.view.updateLimitWarning({ max_connections: 0, effective_max_connections: 2000, truncated: false });
assert.equal(context.limitWarning.style.display, 'none', 'complete automatic scan reported as truncated');
context.view.updateLimitWarning({ max_connections: 500 });
assert.equal(context.limitWarning.style.display, 'block', 'explicit limit warning lost');
assert.match(context.limitWarning.textContent, /500 connections/);
context.view.updateLimitWarning({});
assert.equal(context.limitWarning.style.display, 'none');

console.log('QoS UI regression tests passed.');
