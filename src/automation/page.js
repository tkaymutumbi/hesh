function(command) {
    // Runs in Chromium's isolated application world. No page-owned JS bridge.
    try {
        const visible = e => !!(e.getClientRects().length) && getComputedStyle(e).visibility !== 'hidden';
        const find = selector => {
            if (typeof selector !== 'string' || !selector || selector.length > 1024) throw Error('Provide a CSS selector');
            const matches = [...document.querySelectorAll(selector)].filter(visible);
            if (matches.length !== 1) throw Error('Selector must match exactly one visible element; found ' + matches.length);
            return matches[0];
        };
        const fill = (e, value) => {
            if (!(e instanceof HTMLInputElement || e instanceof HTMLTextAreaElement || e instanceof HTMLSelectElement)) throw Error('Target is not a form field');
            if (e.disabled || e.readOnly || e.type === 'file') throw Error('Field cannot be filled');
            e.focus();
            const proto = e instanceof HTMLTextAreaElement ? HTMLTextAreaElement.prototype : e instanceof HTMLSelectElement ? HTMLSelectElement.prototype : HTMLInputElement.prototype;
            Object.getOwnPropertyDescriptor(proto, 'value').set.call(e, value);
            e.dispatchEvent(new Event('input', {bubbles: true}));
            e.dispatchEvent(new Event('change', {bubbles: true}));
        };
        const selector = e => {
            if (e.id && document.querySelectorAll('#' + CSS.escape(e.id)).length === 1) return '#' + CSS.escape(e.id);
            const path = [];
            while (e && e.nodeType === 1) {
                const tag = e.tagName.toLowerCase();
                const siblings = e.parentElement ? [...e.parentElement.children].filter(s => s.tagName === e.tagName) : [e];
                path.unshift(tag + (siblings.length > 1 ? ':nth-of-type(' + (siblings.indexOf(e) + 1) + ')' : ''));
                if (tag === 'html') break;
                e = e.parentElement;
            }
            return path.join(' > ');
        };
        const snapshot = () => {
            const limit = Math.max(1, Math.min(200, Number(command.limit) || 80));
            const all = [...document.querySelectorAll('a,button,input,textarea,select,[role=button],[role=link]')].filter(visible);
            return {url: location.href, title: document.title, readyState: document.readyState,
                text: (document.body ? document.body.innerText : '').slice(0, 12000),
                elements: all.slice(0, limit).map(e => ({selector: selector(e), tag: e.tagName.toLowerCase(),
                    type: e.getAttribute('type') || '', role: e.getAttribute('role') || '',
                    label: (e.getAttribute('aria-label') || (e.labels && [...e.labels].map(l => l.innerText).join(' ')) || e.innerText || e.getAttribute('placeholder') || e.getAttribute('name') || '').slice(0, 180),
                    disabled: !!e.disabled})), truncated: all.length > limit};
        };
        if (command.action === 'inspect') return JSON.stringify({ok: true, page: snapshot()});
        if (command.action === 'credential_fill') {
            if (location.origin !== command.origin) throw Error('Page origin changed; login was not filled');
            const username = find(command.emailSelector || 'input[type=email],input[autocomplete=username]');
            const password = find(command.passwordSelector || 'input[type=password]');
            if (username === password || username.type === 'password') throw Error('Email and password targets must be different fields');
            if (username.form !== password.form) throw Error('Login fields must belong to the same form');
            // Reject forms posting to a different origin, even on a matching page.
            if (password.form && new URL(password.form.action || location.href, location.href).origin !== location.origin) throw Error('Login form posts to a different origin');
            if (password.type !== 'password') throw Error('Password target must be a password field');
            fill(username, command.email);
            fill(password, command.password);
            return JSON.stringify({ok: true, filled: true, submitted: false});
        }
        if (command.action !== 'interact' || !Array.isArray(command.steps) || command.steps.length < 1 || command.steps.length > 30) throw Error('Provide 1–30 interaction steps');
        const results = [];
        for (let i = 0; i < command.steps.length; i++) {
            try {
                const step = command.steps[i];
                if (step.action === 'stage') {
                    // Paths were staged natively for the page's next file picker.
                } else if (step.action === 'upload') {
                    const matches = [...document.querySelectorAll(step.selector)];
                    if (matches.length !== 1) throw Error('Selector must match exactly one element; found ' + matches.length);
                    const target = matches[0];
                    if (!Array.isArray(step.files) || !step.files.length) throw Error('No files to upload');
                    const list = new DataTransfer();
                    for (const f of step.files) {
                        const bytes = Uint8Array.from(atob(f.data), c => c.charCodeAt(0));
                        list.items.add(new File([bytes], f.name, {type: f.type}));
                    }
                    if (target instanceof HTMLInputElement && target.type === 'file') {
                        if (target.disabled) throw Error('File input is disabled');
                        if (list.files.length > 1 && !target.multiple) throw Error('This input accepts a single file');
                        target.files = list.files;
                        target.dispatchEvent(new Event('input', {bubbles: true}));
                        target.dispatchEvent(new Event('change', {bubbles: true}));
                    } else {
                        // A drop zone: replay the drag sequence with the files.
                        const rect = target.getBoundingClientRect();
                        for (const type of ['dragenter', 'dragover', 'drop']) {
                            target.dispatchEvent(new DragEvent(type, {bubbles: true, cancelable: true, dataTransfer: list,
                                clientX: rect.left + rect.width / 2, clientY: rect.top + rect.height / 2}));
                        }
                    }
                } else if (step.action === 'scroll') {
                    const target = step.selector ? find(step.selector) : window;
                    target.scrollBy({left: Math.max(-10000, Math.min(10000, Number(step.x) || 0)), top: Math.max(-10000, Math.min(10000, Number(step.y) || 0)), behavior: 'instant'});
                } else {
                    const e = find(step.selector);
                    if (step.action === 'click') {
                        if (e.disabled) throw Error('Target is disabled');
                        e.scrollIntoView({block: 'center', behavior: 'instant'}); e.click();
                    } else if (step.action === 'fill') {
                        if (e.type === 'password') throw Error('Use credential_fill for passwords');
                        if (typeof step.value !== 'string' || step.value.length > 20000) throw Error('Fill requires a string of up to 20000 characters');
                        fill(e, step.value);
                    } else if (step.action === 'focus') e.focus();
                    else throw Error('Unknown interaction action');
                }
                results.push({index: i, ok: true});
            } catch (error) {
                results.push({index: i, ok: false, error: String(error.message)});
                return JSON.stringify({ok: false, error: 'Batch stopped; earlier steps may have completed', results});
            }
        }
        return JSON.stringify({ok: true, results, page: snapshot()});
    } catch (error) { return JSON.stringify({ok: false, error: String(error.message)}); }
}
