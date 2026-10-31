const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const test = require('node:test');
const path = require('node:path');

function load() {
    const elements = new Map();
    const document = {};
    function $(selector) {
        if (selector === document) return { ready() {} };
        if (typeof selector === 'object') return selector;
        if (!elements.has(selector)) {
            elements.set(selector, {
                handlers: [],
                value: '',
                visible: false,
                properties: {},
                options: [],
                off() { this.handlers = []; return this; },
                val(value) {
                    if (arguments.length === 0) return this.value;
                    this.value = value;
                    return this;
                },
                toggle(value) { this.visible = value; return this; },
                change(handler) { this.handlers.push(handler); return this; },
                show() { this.visible = true; return this; },
                hide() { this.visible = false; return this; },
                prop(key, value) { this.properties[key] = value; return this; },
                unbind() { return this; },
                click() { return this; },
                empty() { this.options = []; return this; },
                append(value) { this.options.push(value); return this; },
                find() { return { remove() {} }; },
                attr() { return ''; },
                html(value) { this.content = value; return this; },
                text(value) { this.content = value; return this; },
                modal(value) { this.modalState = value; return this; }
            });
        }
        return elements.get(selector);
    }
    const context = { $, document, Option: function(text, value) { this.text = text; this.value = value; } };
    vm.createContext(context);
    vm.runInContext(fs.readFileSync(path.join(__dirname, '..', 'sdr', 'static', 'js', 'config.js'), 'utf8'), context);
    return { context, $ };
}

test('endpoint edits stay with the selected device, including offline devices', () => {
    const { context, $ } = load();
    const first = { connected: false, device_args: { driver: 'rtltcp', rtltcp: 'pi-one:1234' } };
    const second = { device_args: { driver: 'rtltcp', rtltcp: 'pi-two:1235' } };
    context.bindRemoteDevice(first);
    assert.equal($('#remote_device_settings').visible, true);
    context.bindRemoteDevice(second);
    const input = $('#device_rtltcp');
    input.val('  loft-pi:1234  ');
    assert.equal(input.handlers.length, 1);
    input.handlers[0].call(input);
    assert.equal(first.device_args.rtltcp, 'pi-one:1234');
    assert.equal(second.device_args.rtltcp, 'loft-pi:1234');
});

test('local devices hide and detach the endpoint editor without changing their data', () => {
    const { context, $ } = load();
    const remote = { device_args: { driver: 'rtltcp', rtltcp: 'loft-pi:1234' } };
    context.bindRemoteDevice(remote);
    const local = { driver: 'rtlsdr', serial: '00000001' };
    context.bindRemoteDevice(local);
    assert.equal($('#remote_device_settings').visible, false);
    assert.equal($('#device_rtltcp').handlers.length, 0);
    assert.deepEqual(local, { driver: 'rtlsdr', serial: '00000001' });
});

test('disconnected remote devices can be edited without losing their configured sample rate', () => {
    const { context, $ } = load();
    const remote = {
        connected: false, enabled: true, serial: '77465553',
        device_args: { driver: 'rtltcp', rtltcp: 'loft-pi:1234' },
        sample_rate: 1024000, sample_rates: [],
        ranges: [], satellites: [], gains: [], crontabs: [],
        start_recording_level: 12, stop_recording_level: 8
    };
    context.selectDevice({}, remote);
    assert.equal($('#device_section').visible, true);
    assert.equal($('#device_rtltcp').value, 'loft-pi:1234');
    assert.equal($('#device_sample_rate').value, 1024000);
    assert.equal($('#device_sample_rate').options[0].value, 1024000);
});

test('backend validation failures display an error rather than leaving Save spinning', () => {
    const { context, $ } = load();
    const callbacks = {};
    const subscriptions = [];
    const client = {
        on(event, callback) { callbacks[event] = callback; },
        stream: { on() {} },
        subscribe(topic) { subscriptions.push(topic); },
        publish() {}
    };
    context.mqtt = { connect() { return client; } };
    context.console = { log() {} };
    context.connect('ws://localhost');
    callbacks.connect();
    assert.ok(subscriptions.includes('sdr/config/+/failed'));
    callbacks.message('sdr/config/scanner-id/failed', Buffer.alloc(0));
    assert.equal($('#save').content, 'Save');
    assert.match($('#save_success .modal-body').content, /Save failed/);
    assert.equal($('#save_success').modalState, 'show');
    callbacks.message('sdr/config/scanner-id/success', Buffer.alloc(0));
    assert.equal($('#save_success .modal-body').content, 'Save success!');
});
