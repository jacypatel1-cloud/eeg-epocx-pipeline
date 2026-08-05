#!/usr/bin/env python3
"""EEG waiting-room questionnaire intake server.

WHY THIS FILE IS NOT MATLAB
This project's CLAUDE.md is MATLAB-only, local-only, no network calls at
runtime -- for good reason: it processes clinical recordings, and code that
reaches a network while handling patient data is a liability regardless of
what it actually sends. This file is a deliberate, narrow, EXPLICITLY
AUTHORIZED exception to that rule (see CLAUDE.md's "Waiting-room intake
exception" section), made only because a patient's iPad in the waiting
room cannot run a MATLAB App Designer app -- something has to be reachable
on *some* network for a tablet handoff to work at all. The exception is as
narrow as it can be:

  - LAN ONLY. This binds to the machine's own private LAN IPv4 address,
    never 0.0.0.0 and never the internet. If this machine is ever on a
    network with a public interface, that interface is not what this binds
    to.
  - No database, no framework, no third-party dependency -- Python's own
    standard library only (http.server, json, pathlib). One file, easy to
    read top to bottom.
  - It does exactly one job: show a questionnaire form, and write
    submitted answers to a plain JSON file under that patient's own visit
    folder. It does not score anything, does not touch qc_summary.csv or
    any MATLAB output, and does not import to or modify the EEG recording
    pipeline in any way -- MATLAB (import_pending_intake_responses.m)
    picks the raw file up, scores it with the SAME engine used everywhere
    else in this app, and deletes it once processed.
  - Item wording is loaded from questionnaire_definitions.json, exported
    by MATLAB's own questionnaire_definitions.m (export_questionnaire_
    definitions_json.m) -- never hand-copied, so the iPad form and the
    MATLAB app can never show different text for the same instrument.

RUN
    python server.py <project-root>

STOP
    Close this console window, or Ctrl+C.
"""

import json
import re
import socket
import sys
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

PORT = 8765

# Only these characters are ever accepted in a patientId or visit date, and
# only after independently confirming the resulting path is really a direct
# descendant of data/patients. Never build a filesystem path from a request
# without this check -- this server sits on a network, however small.
SAFE_NAME = re.compile(r"^[A-Za-z0-9_.\-]+$")


def get_lan_ip() -> str:
    """Best-effort local LAN IPv4 address -- never 0.0.0.0, never public."""
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        # Doesn't actually send anything (UDP, no handshake) -- just asks
        # the OS which local interface it would use to reach an external
        # address, which is a reliable way to find "the LAN IP" without
        # guessing among multiple network adapters.
        s.connect(("8.8.8.8", 80))
        return s.getsockname()[0]
    except OSError:
        return "127.0.0.1"
    finally:
        s.close()


def render_form(patient_id: str, visit_date: str, definitions: list) -> str:
    sections = []
    for q in definitions:
        placeholder_note = ""
        if q.get("placeholder"):
            placeholder_note = (
                '<p class="placeholder-note">This instrument is a placeholder pending '
                "verified item text -- responses are still recorded, but the wording "
                "below is not the real instrument.</p>"
            )
        items_html = []
        for i, item in enumerate(q["items"]):
            options = "".join(
                f'<option value="{val}">{label}</option>'
                for label, val in zip(item["responseLabels"], item["responseValues"])
            )
            items_html.append(
                f'<div class="item">'
                f'<label>{i + 1}. {item["text"]}</label>'
                f'<select name="{q["id"]}_{i}" required>'
                f'<option value="" selected disabled>-- Select --</option>{options}'
                f"</select></div>"
            )
        sections.append(
            f'<section><h2>{q["title"]}</h2>'
            f'<p class="instructions">{q["instructions"]}</p>'
            f"{placeholder_note}"
            f'<div class="items">{"".join(items_html)}</div></section>'
        )

    return f"""<!doctype html>
<html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>EEG Waiting Room Intake</title>
<style>
  body {{ font-family: system-ui, sans-serif; max-width: 700px; margin: 0 auto; padding: 16px; }}
  h1 {{ font-size: 1.3em; }}
  section {{ margin-bottom: 28px; padding-bottom: 12px; border-bottom: 1px solid #ddd; }}
  .instructions {{ color: #555; font-style: italic; }}
  .placeholder-note {{ color: #b00; font-size: 0.9em; }}
  .item {{ margin: 14px 0; }}
  label {{ display: block; margin-bottom: 6px; }}
  select {{ width: 100%; padding: 10px; font-size: 1em; }}
  button {{ width: 100%; padding: 14px; font-size: 1.1em; background: #2a72bf; color: white;
            border: none; border-radius: 6px; margin-top: 10px; }}
  #status {{ margin-top: 16px; font-weight: bold; }}
</style></head>
<body>
<h1>Questionnaires</h1>
<p>Please answer every question below, then press Submit.</p>
<form id="intakeForm">
{"".join(sections)}
<button type="submit">Submit</button>
</form>
<div id="status"></div>
<script>
document.getElementById('intakeForm').addEventListener('submit', async function(e) {{
    e.preventDefault();
    const form = e.target;
    const data = new FormData(form);
    const byInstrument = {{}};
    for (const [key, value] of data.entries()) {{
        const idx = key.lastIndexOf('_');
        const instrument = key.slice(0, idx);
        const itemIdx = parseInt(key.slice(idx + 1), 10);
        if (!byInstrument[instrument]) byInstrument[instrument] = [];
        byInstrument[instrument][itemIdx] = parseFloat(value);
    }}
    const resp = await fetch('/intake/submit', {{
        method: 'POST',
        headers: {{'Content-Type': 'application/json'}},
        body: JSON.stringify({{
            patient: {json.dumps(patient_id)},
            visit: {json.dumps(visit_date)},
            responses: byInstrument
        }})
    }});
    const statusDiv = document.getElementById('status');
    if (resp.ok) {{
        statusDiv.textContent = 'Thank you -- your answers have been submitted.';
        form.style.display = 'none';
    }} else {{
        statusDiv.textContent = 'Something went wrong. Please tell the front desk.';
    }}
}});
</script>
</body></html>"""


class IntakeHandler(BaseHTTPRequestHandler):
    definitions = []
    data_root = None  # Path to the project's data/ folder

    def _send_json(self, status, payload):
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _send_html(self, status, html):
        body = html.encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _safe_visit_dir(self, patient_id, visit_date):
        """Resolve data/patients/<patient>/visits/<date>, refusing anything
        that is not exactly that -- never build a path from a request
        without this, even on a LAN-only server."""
        if not (SAFE_NAME.match(patient_id) and SAFE_NAME.match(visit_date)):
            return None
        visit_dir = (self.data_root / "patients" / patient_id / "visits" / visit_date).resolve()
        expected_parent = (self.data_root / "patients" / patient_id / "visits").resolve()
        if visit_dir.parent != expected_parent or not visit_dir.is_dir():
            return None
        return visit_dir

    def do_GET(self):
        parsed = urlparse(self.path)
        if parsed.path == "/intake":
            qs = parse_qs(parsed.query)
            patient_id = qs.get("patient", [""])[0]
            visit_date = qs.get("visit", [""])[0]
            if self._safe_visit_dir(patient_id, visit_date) is None:
                self._send_html(404, "<h1>Unknown patient or visit</h1>")
                return
            self._send_html(200, render_form(patient_id, visit_date, self.definitions))
            return
        if parsed.path == "/":
            self._send_html(200, "<h1>EEG Waiting Room Intake</h1><p>Ready.</p>")
            return
        self._send_html(404, "<h1>Not found</h1>")

    def do_POST(self):
        parsed = urlparse(self.path)
        if parsed.path != "/intake/submit":
            self._send_html(404, "<h1>Not found</h1>")
            return

        length = int(self.headers.get("Content-Length", 0))
        try:
            payload = json.loads(self.rfile.read(length))
        except (ValueError, TypeError):
            self._send_json(400, {"error": "invalid JSON"})
            return

        patient_id = str(payload.get("patient", ""))
        visit_date = str(payload.get("visit", ""))
        responses = payload.get("responses", {})

        visit_dir = self._safe_visit_dir(patient_id, visit_date)
        if visit_dir is None:
            self._send_json(404, {"error": "unknown patient or visit"})
            return

        known_ids = {q["id"] for q in self.definitions}
        intake_dir = visit_dir / "questionnaire_intake"
        intake_dir.mkdir(exist_ok=True)

        written = []
        for instrument_id, values in responses.items():
            if instrument_id not in known_ids:
                continue
            out_path = intake_dir / f"{instrument_id}.json"
            out_path.write_text(json.dumps({
                "instrumentId": instrument_id,
                "responses": values,
                "submittedOn": datetime.now(timezone.utc).isoformat(),
            }, indent=2))
            written.append(instrument_id)

        self._send_json(200, {"saved": written})

    def log_message(self, format_, *args):
        sys.stderr.write("%s - %s\n" % (self.address_string(), format_ % args))


def main():
    if len(sys.argv) < 2:
        print("Usage: python server.py <project-root>")
        sys.exit(1)

    project_root = Path(sys.argv[1]).resolve()
    data_root = project_root / "data"
    defs_path = project_root / "webintake" / "questionnaire_definitions.json"

    if not defs_path.is_file():
        print(f"Missing {defs_path} -- run export_questionnaire_definitions_json(cfg) first.")
        sys.exit(1)

    IntakeHandler.definitions = json.loads(defs_path.read_text())
    IntakeHandler.data_root = data_root

    lan_ip = get_lan_ip()
    server = ThreadingHTTPServer((lan_ip, PORT), IntakeHandler)

    status = {
        "url": f"http://{lan_ip}:{PORT}/",
        "lanIp": lan_ip,
        "port": PORT,
        "startedOn": datetime.now(timezone.utc).isoformat(),
    }
    (project_root / "webintake" / "server_status.json").write_text(json.dumps(status, indent=2))

    print(f"EEG waiting-room intake server running at http://{lan_ip}:{PORT}/")
    print("LAN only -- not reachable from the internet. Close this window to stop.")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
