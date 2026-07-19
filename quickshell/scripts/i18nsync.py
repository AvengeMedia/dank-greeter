#!/usr/bin/env python3

import sys
import json
import os
import subprocess
from pathlib import Path
from urllib import request, parse

REPO_ROOT = Path(__file__).parent.parent
EN_JSON = REPO_ROOT / "translations" / "en.json"
TEMPLATE_JSON = REPO_ROOT / "translations" / "template.json"
POEXPORTS_DIR = REPO_ROOT / "translations" / "poexports"
SYNC_STATE = REPO_ROOT.parent / ".git" / "i18n_sync_state.json"

# dms-greeter terms live in the shared DMS POEditor project under this tag.
# Everything here is tag-scoped: uploads union tags on existing terms, prune
# deletes only dms-greeter-tagged terms, downloads export only the tag.
# dank-qml-common translations ship inside the submodule and are not synced
# from this repo.
APP_TAG = "dms-greeter"

LANGUAGES = {
    "ja": "ja.json",
    "zh-Hans": "zh_CN.json",
    "zh-Hant": "zh_TW.json",
    "pt-br": "pt.json",
    "tr": "tr.json",
    "it": "it.json",
    "pl": "pl.json",
    "es": "es.json",
    "he": "he.json",
    "hu": "hu.json",
    "fa": "fa.json",
    "fr": "fr.json",
    "nl": "nl.json",
    "ru": "ru.json",
    "de": "de.json",
    "sv": "sv.json",
    "vi": "vi.json",
    "eo": "eo.json",
    "ko": "ko.json",
    "ar": "ar.json"
}

def error(msg):
    print(f"\033[91mError: {msg}\033[0m", file=sys.stderr)
    sys.exit(1)

def warn(msg):
    print(f"\033[93mWarning: {msg}\033[0m", file=sys.stderr)

def info(msg):
    print(f"\033[94m{msg}\033[0m")

def success(msg):
    print(f"\033[92m{msg}\033[0m")

def get_env_or_error(var):
    value = os.environ.get(var)
    if not value:
        error(f"{var} environment variable not set")
    return value

def poeditor_request(endpoint, data):
    url = f"https://api.poeditor.com/v2/{endpoint}"
    data_bytes = parse.urlencode(data).encode()
    req = request.Request(url, data=data_bytes, method="POST")

    try:
        with request.urlopen(req) as response:
            return json.loads(response.read().decode())
    except Exception as e:
        error(f"POEditor API request failed: {e}")

def extract_strings():
    info("Extracting strings from QML files...")
    extract_script = REPO_ROOT / "translations" / "extract_translations.py"

    if not extract_script.exists():
        error(f"Extract script not found: {extract_script}")

    result = subprocess.run([sys.executable, str(extract_script)], cwd=REPO_ROOT)
    if result.returncode != 0:
        error("String extraction failed")

    if not EN_JSON.exists():
        error(f"Extraction did not produce {EN_JSON}")

def normalize_json(file_path):
    if not file_path.exists():
        return {}
    with open(file_path) as f:
        return json.load(f)

def json_changed(file_path, new_data):
    old_data = normalize_json(file_path)
    return json.dumps(old_data, sort_keys=True) != json.dumps(new_data, sort_keys=True)

def entry_key(entry):
    return (entry.get('context') or entry['term'], entry['term'])

def list_remote_terms(api_token, project_id):
    resp = poeditor_request('terms/list', {
        'api_token': api_token,
        'id': project_id
    })
    if resp.get('response', {}).get('status') != 'success':
        error(f"POEditor terms list failed: {resp}")
    return resp.get('result', {}).get('terms', [])

def tag_entries(entries, remote_terms):
    remote_tags = {entry_key(t): t.get('tags', []) for t in remote_terms}
    tagged = []
    for entry in entries:
        merged = set(entry.get('tags', [])) | set(remote_tags.get(entry_key(entry), [])) | {APP_TAG}
        tagged.append({**entry, "tags": sorted(merged)})
    return tagged

def upload_source_strings(api_token, project_id, entries):
    if not entries:
        warn("No terms to upload")
        return False

    info("Uploading source strings to POEditor...")

    upload_bytes = json.dumps(entries, ensure_ascii=False).encode()
    boundary = '----WebKitFormBoundary7MA4YWxkTrZu0gW'
    body = (
        f'--{boundary}\r\n'
        f'Content-Disposition: form-data; name="api_token"\r\n\r\n'
        f'{api_token}\r\n'
        f'--{boundary}\r\n'
        f'Content-Disposition: form-data; name="id"\r\n\r\n'
        f'{project_id}\r\n'
        f'--{boundary}\r\n'
        f'Content-Disposition: form-data; name="updating"\r\n\r\n'
        f'terms\r\n'
        f'--{boundary}\r\n'
        f'Content-Disposition: form-data; name="file"; filename="en.json"\r\n'
        f'Content-Type: application/json\r\n\r\n'
    ).encode() + upload_bytes + f'\r\n--{boundary}--\r\n'.encode()

    req = request.Request(
        'https://api.poeditor.com/v2/projects/upload',
        data=body,
        headers={'Content-Type': f'multipart/form-data; boundary={boundary}'}
    )

    try:
        with request.urlopen(req) as response:
            result = json.loads(response.read().decode())
    except Exception as e:
        error(f"Upload failed: {e}")

    if result.get('response', {}).get('status') != 'success':
        error(f"POEditor upload failed: {result}")

    terms = result.get('result', {}).get('terms', {})
    added = terms.get('added', 0)
    updated = terms.get('updated', 0)

    if added or updated:
        success(f"POEditor updated: {added} added, {updated} updated")
        return True
    info("No changes uploaded to POEditor")
    return False

def prune_remote_terms(api_token, project_id, local_entries, remote_terms):
    local_keys = {entry_key(e) for e in local_entries}
    stale = [t for t in remote_terms
             if APP_TAG in t.get('tags', []) and entry_key(t) not in local_keys]
    if not stale:
        info("No stale dms-greeter terms to prune")
        return

    warn(f"Deleting {len(stale)} POEditor terms tagged {APP_TAG} that are missing locally")
    payload = json.dumps([{'term': t['term'], 'context': t.get('context', '')} for t in stale])
    resp = poeditor_request('terms/delete', {
        'api_token': api_token,
        'id': project_id,
        'data': payload
    })
    if resp.get('response', {}).get('status') != 'success':
        error(f"POEditor terms delete failed: {resp}")
    success(f"Pruned {len(stale)} terms")

def write_if_changed(repo_file, new_data):
    if not json_changed(repo_file, new_data):
        return False
    with open(repo_file, 'w') as f:
        json.dump(new_data, f, ensure_ascii=False, indent=2, sort_keys=True)
        f.write('\n')
    return True

def download_translations(api_token, project_id):
    info("Downloading translations from POEditor...")

    POEXPORTS_DIR.mkdir(parents=True, exist_ok=True)
    any_changed = False

    for po_lang, filename in LANGUAGES.items():
        repo_file = POEXPORTS_DIR / filename

        info(f"Fetching {po_lang}...")

        export_resp = poeditor_request('projects/export', {
            'api_token': api_token,
            'id': project_id,
            'language': po_lang,
            'type': 'key_value_json',
            'tags': APP_TAG
        })

        if export_resp.get('response', {}).get('status') != 'success':
            warn(f"Export request failed for {po_lang}")
            continue

        url = export_resp.get('result', {}).get('url')
        if not url:
            warn(f"No export URL for {po_lang}")
            continue

        try:
            with request.urlopen(url) as response:
                new_data = json.loads(response.read().decode())
        except Exception as e:
            warn(f"Failed to download {po_lang}: {e}")
            continue

        if write_if_changed(repo_file, new_data):
            success(f"Updated {filename}")
            any_changed = True
        else:
            info(f"No changes for {filename}")

    return any_changed

def check_sync_status():
    api_token = get_env_or_error('POEDITOR_API_TOKEN')
    project_id = get_env_or_error('POEDITOR_PROJECT_ID')

    extract_strings()

    current_en = normalize_json(EN_JSON)

    if not SYNC_STATE.exists():
        return True

    with open(SYNC_STATE) as f:
        state = json.load(f)

    if json.dumps(current_en, sort_keys=True) != json.dumps(state.get('en_json', {}), sort_keys=True):
        return True

    last_translations = state.get('translations', {})
    for filename in LANGUAGES.values():
        if json_changed(POEXPORTS_DIR / filename, last_translations.get(filename, {})):
            return True

    first_lang = list(LANGUAGES.keys())[0]
    export_resp = poeditor_request('projects/export', {
        'api_token': api_token,
        'id': project_id,
        'language': first_lang,
        'type': 'key_value_json',
        'tags': APP_TAG
    })

    if export_resp.get('response', {}).get('status') != 'success':
        return False

    url = export_resp.get('result', {}).get('url')
    if not url:
        return False

    try:
        with request.urlopen(url) as response:
            remote_data = json.loads(response.read().decode())
        return json_changed(POEXPORTS_DIR / LANGUAGES[first_lang], remote_data)
    except Exception:
        return False

def save_sync_state():
    state = {
        'en_json': normalize_json(EN_JSON),
        'translations': {}
    }

    for filename in LANGUAGES.values():
        state['translations'][filename] = normalize_json(POEXPORTS_DIR / filename)

    SYNC_STATE.parent.mkdir(parents=True, exist_ok=True)
    with open(SYNC_STATE, 'w') as f:
        json.dump(state, f, indent=2)

def run_sync(force_upload, prune):
    api_token = get_env_or_error('POEDITOR_API_TOKEN')
    project_id = get_env_or_error('POEDITOR_PROJECT_ID')

    extract_strings()
    current_en = normalize_json(EN_JSON)

    last_en = {}
    if SYNC_STATE.exists():
        with open(SYNC_STATE) as f:
            last_en = json.load(f).get('en_json', {})
    strings_changed = json.dumps(current_en, sort_keys=True) != json.dumps(last_en, sort_keys=True)

    if strings_changed or force_upload or prune:
        remote_terms = list_remote_terms(api_token, project_id)
        upload_source_strings(api_token, project_id, tag_entries(current_en, remote_terms))
        if prune:
            prune_remote_terms(api_token, project_id, current_en, remote_terms)
    else:
        info("No changes in source strings")

    translations_changed = download_translations(api_token, project_id)

    if strings_changed or translations_changed:
        subprocess.run(['git', 'add', 'translations/'], cwd=REPO_ROOT)
        save_sync_state()
        success("Sync complete - changes staged for commit")
        return

    save_sync_state()
    info("Already in sync")

def run_local():
    info("Updating en.json locally (no POEditor sync)")

    old_en = normalize_json(EN_JSON)
    old_terms = {entry['term']: entry for entry in old_en} if isinstance(old_en, list) else {}

    extract_strings()

    new_en = normalize_json(EN_JSON)
    new_terms = {entry['term']: entry for entry in new_en} if isinstance(new_en, list) else {}

    added = set(new_terms.keys()) - set(old_terms.keys())
    removed = set(old_terms.keys()) - set(new_terms.keys())

    if added:
        info(f"\n+{len(added)} new terms:")
        for term in sorted(added)[:20]:
            print(f"  + {term[:60]}...")
        if len(added) > 20:
            print(f"  ... and {len(added) - 20} more")

    if removed:
        info(f"\n-{len(removed)} removed terms:")
        for term in sorted(removed)[:20]:
            print(f"  - {term[:60]}...")
        if len(removed) > 20:
            print(f"  ... and {len(removed) - 20} more")

    success(f"\n✓ {len(new_en)} total terms")

    if not added and not removed:
        info("No changes detected")

def run_test():
    info("Running in test mode (no POEditor upload/download)")
    extract_strings()

    current_en = normalize_json(EN_JSON)

    success(f"✓ Extracted {len(current_en)} terms")

    terms_with_context = sum(1 for entry in current_en if entry.get('context') and entry['context'] != entry['term'])
    if terms_with_context > 0:
        success(f"✓ Found {terms_with_context} terms with custom contexts")

    info("\nFiles generated:")
    info(f"  - {EN_JSON}")
    info(f"  - {TEMPLATE_JSON}")

def main():
    if len(sys.argv) < 2:
        error("Usage: i18nsync.py [check|sync [--prune]|push|test|local]")

    command = sys.argv[1]

    match command:
        case "test":
            run_test()
        case "local":
            run_local()
        case "check":
            try:
                if check_sync_status():
                    error("i18n out of sync - run 'python3 scripts/i18nsync.py sync' first")
                success("i18n in sync")
            except SystemExit:
                raise
            except Exception as e:
                error(f"Check failed: {e}")
        case "sync":
            run_sync(force_upload=False, prune="--prune" in sys.argv[2:])
        case "push":
            run_sync(force_upload=True, prune=False)
        case _:
            error(f"Unknown command: {command}")

if __name__ == '__main__':
    main()
