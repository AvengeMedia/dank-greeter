const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync(process.argv[2], 'utf8');

// Execute the QML's authentication functions with a deterministic clock and greetd peer.
function functionSource(name) {
    const match = source.match(new RegExp(`^([ \\t]*)function ${name}\\(`, 'm'));
    assert(match, `missing function ${name}`);
    const end = source.indexOf(`\n${match[1]}}`, match.index);
    assert(end >= 0, `missing end of ${name}`);
    return source.slice(match.index, end + match[1].length + 2).trim();
}

function propertyExpression(name) {
    const match = source.match(new RegExp(`property (?:bool|int) ${name}: ([^\\n]+)`));
    assert(match, `missing property ${name}`);
    return match[1];
}

function session(pamText, included = {}) {
    let now = 0;
    let deadline = 0;
    let cancelled = 0;
    const responses = [];
    const context = {
        greetdPamText: pamText,
        systemAuthPamText: '', commonAuthPamText: '', passwordAuthPamText: '',
        systemLoginPamText: '', systemLocalLoginPamText: '', commonAuthPcPamText: '', loginPamText: '',
        ...included,
        GreeterState: {showPasswordInput: true, username: 'test-user', passwordBuffer: '', unlocking: false},
        GreetdState: {Inactive: 0},
        Greetd: {
            state: 0,
            createSession() { this.state = 1; },
            cancelSession() { cancelled++; this.state = 0; },
            respond(value) { responses.push(value); },
        },
        defaultAuthTimeoutMs: Number(propertyExpression('defaultAuthTimeoutMs')),
        externalAuthTimeoutMs: Number(propertyExpression('externalAuthTimeoutMs')),
        greeterPamHasFprint: false, greeterPamHasU2f: false,
        SettingsData: {greeterEnableFprint: false, greeterEnableU2f: false},
        awaitingExternalAuth: false, pendingPasswordResponse: false, passwordSubmitRequested: false,
        authTimeout: {
            interval: 0, running: false,
            restart() { this.running = true; deadline = now + this.interval; },
            stop() { this.running = false; },
        },
        clearInput() {}, currentAuthMessage() { return 'authentication error'; },
        placeholderDelay: {restart() {}},
    };
    context.root = context;
    vm.createContext(context);
    for (const name of ['stripPamComment', 'pamModuleEnabled', 'pamTextIncludesFile',
        'greeterPamStackHasModule', 'submitBufferedPassword', 'startAuthSession', 'onAuthMessage']) {
        vm.runInContext(functionSource(name), context);
    }
    for (const name of ['greeterPamHasFaceAuth', 'greeterExternalAuthAvailable', 'greeterPamHasExternalAuth']) {
        context[name] = vm.runInContext(propertyExpression(name), context);
    }
    const timer = source.match(/Timer\s*\{\s*id: authTimeout\b([\s\S]*?)\n    \}/);
    assert(timer, 'missing authentication timeout handler');
    const body = timer[1].match(/onTriggered:\s*(\{[\s\S]*\})/);
    assert(body, 'missing authentication timeout body');
    vm.runInContext(`function expireAuth() ${body[1]}`, context);
    return {
        context, responses,
        advance(ms) {
            now += ms;
            if (context.authTimeout.running && now >= deadline) {
                context.authTimeout.running = false;
                context.expireAuth();
            }
        },
        cancelled() { return cancelled; },
    };
}

for (const [name, pam, included] of [
    ['direct Smile2Unlock', 'auth sufficient pam_smile2unlock.so\nauth include system-local-login', {}],
    ['included Smile2Unlock', 'auth include system-auth', {systemAuthPamText: 'auth sufficient pam_smile2unlock.so'}],
    ['existing face module', 'auth sufficient pam_howdy.so', {}],
]) {
    const attempt = session(pam, included);
    attempt.context.GreeterState.passwordBuffer = 'test-password';
    attempt.context.startAuthSession(true);
    attempt.advance(12000);
    assert.equal(attempt.cancelled(), 0, `${name}: cancelled before face recognition returned`);
    assert.equal(attempt.context.GreeterState.passwordBuffer, 'test-password', `${name}: erased buffered password`);
    attempt.context.onAuthMessage('Password:', false, true, false);
    assert.deepEqual(attempt.responses, ['test-password'], `${name}: password did not reach PAM`);
    assert.equal(attempt.context.GreeterState.passwordBuffer, '', `${name}: submitted password retained`);
}

const automatic = session('auth sufficient pam_smile2unlock.so');
automatic.context.startAuthSession(false);
assert.equal(automatic.context.Greetd.state, 1, 'face authentication did not start');
automatic.advance(12000);
assert.equal(automatic.cancelled(), 0, 'automatic face attempt cancelled before fallback');
automatic.context.onAuthMessage('Password:', false, true, false);
assert.equal(automatic.context.pendingPasswordResponse, true);
assert.equal(automatic.context.authTimeout.running, false, 'password entry must wait for the user');
automatic.context.GreeterState.passwordBuffer = 'test-password';
automatic.context.startAuthSession(true);
assert.deepEqual(automatic.responses, ['test-password']);

for (const pam of ['auth include system-auth', '# auth sufficient pam_smile2unlock.so\nauth include system-auth']) {
    const passwordOnly = session(pam);
    passwordOnly.context.GreeterState.passwordBuffer = 'test-password';
    passwordOnly.context.startAuthSession(true);
    passwordOnly.advance(12000);
    assert.equal(passwordOnly.cancelled(), 1, 'ordinary password authentication must retain its timeout');
}
