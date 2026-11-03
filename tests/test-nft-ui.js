'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const repo = path.resolve(__dirname, '..');
const uiRoot = path.join(repo, 'luci-app-multiwan-nft');
let jsCount = 0, jsonCount = 0;

function checkSyntax(directory) {
    for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
        const file = path.join(directory, entry.name);
        if (entry.isDirectory()) checkSyntax(file);
        else if (file.endsWith('.js')) {
            new Function(fs.readFileSync(file, 'utf8'));
            jsCount++;
        } else if (file.endsWith('.json')) {
            JSON.parse(fs.readFileSync(file, 'utf8'));
            jsonCount++;
        }
    }
}
checkSyntax(uiRoot);

function renderNetworkView(name, data) {
    const options = {};
    const formvalues = {};
    const section = {
        option(type, name) {
            return options[name] = {
                dependencies: [], choices: [],
                depends(field, value) { this.dependencies.push([field, value]); },
                value(value) { this.choices.push(value); },
                formvalue(sectionId) { return formvalues[sectionId]?.[name]; }
            };
        }
    };
    const context = vm.createContext({
        view: { extend: value => value }, _: value => value,
        form: { Map: function () { this.section = () => section; this.render = () => options; } },
        uci: { sections: () => [], get: () => undefined }, ui: {}, fs: {}
    });
    vm.runInContext('String.prototype.format = function () { return String(this); };', context);
    const file = path.join(uiRoot, 'htdocs/luci-static/resources/view/multiwan-nft/network', name + '.js');
    vm.runInContext('(function () {\n' + fs.readFileSync(file, 'utf8') + '\n})()', context).render(data);
    return { options, formvalues };
}

const minimal = renderNetworkView('interface', [{}, {}, {}]).options;
assert.deepEqual(minimal.track_method.choices, ['ping', 'nslookup']);
const { options: iface, formvalues } = renderNetworkView('interface', [
    { type: 'file' }, { type: 'file' }, { type: 'file' }
]);
for (const method of ['ping', 'httping', 'arping', 'nping-tcp', 'nping-udp', 'nping-icmp', 'nping-arp'])
    assert.ok(iface.track_method.choices.includes(method), method);
assert.deepEqual(iface.check_quality.dependencies, [['track_method', 'ping'], ['track_method', 'httping']]);
assert.equal(iface.check_quality.default, false);
assert.deepEqual(iface.httping_ssl.dependencies, [['track_method', 'httping']]);
assert.equal(iface.family.default, 'ipv4');
assert.equal(iface.initial_state.default, 'online');
assert.equal(iface.track_ip.datatype, 'host');
assert.equal(iface.reliability.default, '1');
assert.equal(iface.reliability.datatype, 'range(1, 100)');

for (const [name, good, bad] of [
    ['failure_latency', '1000', '499'], ['recovery_latency', '500', '1001'],
    ['failure_loss', '40', '9'], ['recovery_loss', '10', '41']
]) {
    assert.equal(iface[name].validate('wan', good), true, name);
    assert.notEqual(iface[name].validate('wan', bad), true, name);
    assert.deepEqual(iface[name].dependencies, [['check_quality', '1']]);
}
formvalues.wan = { failure_latency: '300', recovery_latency: '200', failure_loss: '0', recovery_loss: '0' };
assert.equal(iface.failure_latency.validate('wan', '200'), true);
assert.notEqual(iface.failure_latency.validate('wan', '199'), true);
assert.equal(iface.recovery_latency.validate('wan', '300'), true);
assert.notEqual(iface.recovery_latency.validate('wan', '301'), true);
assert.equal(iface.failure_loss.validate('wan', '0'), true);
assert.equal(iface.recovery_loss.validate('wan', '0'), true);
assert.notEqual(iface.recovery_loss.validate('wan', '1'), true);

const globals = renderNetworkView('globals').options;
assert.equal(globals.mmx_mask.default, '0x3F0000');
for (const mask of ['0x3F0000', '0x00FC0000', '0x1500', '0x80000300'])
    assert.equal(globals.mmx_mask.validate('globals', mask), true, mask);
for (const mask of ['', 'garbage', '0xFF', '0x30000', '0xFFFFFFFF', '0x100000000'])
    assert.notEqual(globals.mmx_mask.validate('globals', mask), true, mask);

const rule = renderNetworkView('rule', ['youtube\n']).options;
assert.equal(rule.timeout.datatype, 'range(1, 1000000)');
assert.equal(rule.sticky.default, '0');
assert.equal(rule.proto.default, 'all');
assert.equal(rule.src_ip.datatype, 'ipaddr');
assert.equal(rule.dest_ip.datatype, 'ipaddr');

const acl = JSON.parse(fs.readFileSync(path.join(uiRoot,
    'root/usr/share/rpcd/acl.d/luci-app-multiwan-nft.json'), 'utf8'))['luci-app-multiwan-nft'];
for (const action of ['ifup', 'ifdown']) {
    const command = `/usr/sbin/multiwan-nft ${action} *`;
    assert.equal(acl.read.file[command], undefined, 'Read-only sessions must not change WAN state');
    assert.ok(acl.write.file[command].includes('exec'), 'Administrators must retain WAN controls');
}
assert.ok(acl.read.ubus.file?.includes('exec'), 'Safe diagnostics require both the file.exec RPC method and command permissions');

function checkStatusRendering() {
    const context = vm.createContext({
        _: value => value, L: { resource: value => value },
        rpc: { declare: () => () => Promise.resolve({}) },
        baseclass: { extend: value => value },
        document: { querySelector: () => ({ appendChild() {} }) },
        E: (tag, attrs, children = []) => ({ tag, attrs, children,
            appendChild(child) { this.children.push(child); } })
    });
    vm.runInContext('String.prototype.format = function (...args) { let i = 0; return String(this).replace(/%[hst]/g, () => String(args[i++])); };', context);
    const overview = fs.readFileSync(path.join(uiRoot, 'htdocs/luci-static/resources/view/multiwan-nft/status/overview.js'), 'utf8');
    const render = vm.runInContext('(function () {\n' + overview.slice(0, overview.indexOf('\nreturn view.extend')) + '\nreturn renderMwan3Status; })()', context);
    const widgetSource = fs.readFileSync(path.join(uiRoot, 'htdocs/luci-static/resources/view/status/include/90_multiwan_nft.js'), 'utf8');
    const widget = vm.runInContext('(function () {\n' + widgetSource + '\n})()', context);
    const stopped = { running: false, interfaces: { wan: { status: 'online' } } };
    assert.match(render(stopped), /MultiWAN routing is stopped/);
    assert.match(JSON.stringify(widget.render([stopped])), /MultiWAN routing is stopped/);
    for (const running of [false, true]) {
        const pending = { running, reconfiguration_pending: true, interfaces: { wan: { status: 'online' } } };
        assert.match(render(pending), /Routing configuration is incomplete/);
        assert.match(JSON.stringify(widget.render([pending])), /Routing configuration is incomplete/);
        if (running) {
            assert.match(render(pending), /Online/);
            assert.match(JSON.stringify(widget.render([pending])), /Online/);
            assert.doesNotMatch(render(pending), /routing is stopped/);
        }
    }
    assert.doesNotMatch(render({ running: true, reconfiguration_pending: false, interfaces: {} }), /configuration is incomplete/);
    for (const [status, label] of [['connecting','Connecting'], ['disconnecting','Disconnecting'], ['waiting','Waiting for interface'], ['disabled','Disabled'], ['unknown','Unknown']]) {
        const data = { running: true, interfaces: { wan: { status } } };
        assert.ok(render(data).includes(label), 'Overview state: ' + status);
        assert.ok(JSON.stringify(widget.render([data])).includes(label), 'Widget state: ' + status);
    }
}
checkStatusRendering();

async function checkDiagnosticPermissions() {
    const source = fs.readFileSync(path.join(uiRoot,
        'htdocs/luci-static/resources/view/multiwan-nft/status/diagnostics.js'), 'utf8');
    for (const writable of [false, true]) {
        let selectedTask = 'gateway';
        const commands = [];
        const context = vm.createContext({
            view: { extend: value => value }, _: value => value,
            L: { hasViewPermission: () => writable },
            E: (tag, attrs, children) => ({ tag, attrs, children }),
            uci: { sections: () => [{ '.name': 'wan' }] },
            ui: { createHandlerFn: () => () => {} }, fs: {}, dom: {},
            document: { getElementById: id => ({ value: id === 'iface' ? 'wan' : selectedTask }) }
        });
        const view = vm.runInContext('(function () {\n' + source + '\n})()', context);
        const tree = view.render();
        function findTask(node) {
            if (!node || typeof node !== 'object') return undefined;
            if (node.attrs?.id === 'task') return node;
            for (const child of node.children || []) {
                const found = findTask(child);
                if (found) return found;
            }
        }
        const choices = Array.from(findTask(tree).children, option => option.attrs.value);
        assert.equal(choices.includes('ifup'), writable);
        assert.equal(choices.includes('ifdown'), writable);
        view.handleCommand = (command, args) => { commands.push([command, ...args]); return Promise.resolve(); };
        await view.handleAction({});
        assert.equal(commands.length, 1, 'Read-only sessions must retain safe diagnostics');
        for (const action of ['ifup', 'ifdown']) {
            selectedTask = action;
            if (writable) {
                await view.handleAction({});
                assert.deepEqual(commands.at(-1), ['/usr/sbin/multiwan-nft', action, 'wan']);
            } else {
                await assert.rejects(view.handleAction({}), /Write access is required/);
                assert.equal(commands.length, 1, 'Tampered task selection bypassed read-only guard');
            }
        }
    }
}

checkDiagnosticPermissions().then(() => {
    console.log(`NFT UI tests passed: ${jsCount} JavaScript files, ${jsonCount} JSON files, quality controls, validators, ACL, and diagnostics permissions.`);
}).catch(error => { console.error(error); process.exitCode = 1; });
