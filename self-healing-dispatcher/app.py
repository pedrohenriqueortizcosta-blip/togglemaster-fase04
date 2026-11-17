import os
import sys
import logging
import requests
from flask import Flask, request, jsonify

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s')
log = logging.getLogger(__name__)

app = Flask(__name__)

# --- Configuração ---
# GITHUB_TOKEN é o único segredo real aqui — nunca logado, nunca
# retornado em nenhuma resposta.
GITHUB_TOKEN = os.getenv("GITHUB_TOKEN")
GITHUB_REPO = os.getenv("GITHUB_REPO")  # formato "owner/repo"

if not all([GITHUB_TOKEN, GITHUB_REPO]):
    log.critical("Erro: GITHUB_TOKEN e GITHUB_REPO devem ser definidos.")
    sys.exit(1)

DISPATCH_URL = f"https://api.github.com/repos/{GITHUB_REPO}/dispatches"


@app.route('/health')
def health():
    return jsonify({"status": "ok"})


@app.route('/webhook', methods=['POST'])
def alertmanager_webhook():
    """
    Recebe o payload de webhook do Alertmanager e, para cada alerta com
    status "firing", dispara um evento repository_dispatch no GitHub —
    que por sua vez aciona a Action de self-healing (reaproveitando a
    federação OIDC GitHub<->AWS já existente, sem token/role novo).

    Alertas com status "resolved" são ignorados de propósito: self-healing
    deve reagir ao INÍCIO do problema, não à sua resolução.
    """
    payload = request.get_json(silent=True)
    if not payload:
        return jsonify({"error": "corpo da requisição inválido"}), 400

    alerts = payload.get("alerts", [])
    dispatched = []

    for alert in alerts:
        if alert.get("status") != "firing":
            continue

        labels = alert.get("labels", {})
        alertname = labels.get("alertname", "unknown")
        service = labels.get("service", "unknown")

        log.info(f"Alerta 'firing' recebido: {alertname} (service: {service})")

        try:
            response = requests.post(
                DISPATCH_URL,
                headers={
                    "Authorization": f"Bearer {GITHUB_TOKEN}",
                    "Accept": "application/vnd.github+json",
                },
                json={
                    "event_type": "self-heal",
                    "client_payload": {
                        "service": service,
                        "alertname": alertname,
                    },
                },
                timeout=10,
            )
            if response.status_code == 204:
                log.info(
                    f"repository_dispatch disparado com sucesso para '{service}' "
                    f"(alerta: {alertname})")
                dispatched.append(service)
            else:
                log.error(
                    f"GitHub API retornou status {response.status_code} ao "
                    f"disparar repository_dispatch: {response.text}")
        except requests.exceptions.RequestException as e:
            log.error(f"Erro ao chamar a API do GitHub: {e}")

    return jsonify({"dispatched": dispatched}), 200


if __name__ == '__main__':
    port = int(os.getenv("PORT", 8006))
    app.run(host='0.0.0.0', port=port, debug=False)
