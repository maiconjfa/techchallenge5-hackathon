"""Testes unitarios das rotas do volunteer-service (sem AWS real)."""

VOLUNTEER_PAYLOAD = {
    "name": "Maria Silva",
    "email": "maria@example.org",
    "ngo_id": 10,
}


def test_health_returns_service_status(client):
    response = client.get("/health")

    assert response.status_code == 200
    assert response.get_json() == {"status": "ok", "service": "volunteer-service"}


def test_register_volunteer_rejects_missing_fields(client):
    response = client.post("/volunteers", json={"name": "Sem email"})

    assert response.status_code == 400
    assert response.get_json()["error"] == "Campos obrigatórios ausentes"


def test_register_volunteer_persists_and_returns_201(client, table):
    response = client.post("/volunteers", json=VOLUNTEER_PAYLOAD)

    assert response.status_code == 201
    body = response.get_json()
    assert body["name"] == VOLUNTEER_PAYLOAD["name"]
    assert body["ngo_id"] == VOLUNTEER_PAYLOAD["ngo_id"]
    assert body["volunteer_id"]

    item = table.put_item.call_args.kwargs["Item"]
    assert item["volunteer_id"] == body["volunteer_id"]
    assert item["ngo_id"] == VOLUNTEER_PAYLOAD["ngo_id"]


def test_register_volunteer_returns_500_on_dynamodb_error(client, table):
    table.put_item.side_effect = RuntimeError("throttling")

    response = client.post("/volunteers", json=VOLUNTEER_PAYLOAD)

    assert response.status_code == 500
    assert response.get_json()["error"] == "Erro interno ao processar dados"


def test_list_volunteers_by_ngo_returns_items(client, table):
    table.scan.return_value = {"Items": [{"volunteer_id": "abc", "ngo_id": 10}]}

    response = client.get("/volunteers/10")

    assert response.status_code == 200
    assert response.get_json() == [{"volunteer_id": "abc", "ngo_id": 10}]
    table.scan.assert_called_once()


def test_list_volunteers_returns_500_on_dynamodb_error(client, table):
    table.scan.side_effect = RuntimeError("tabela indisponivel")

    response = client.get("/volunteers/10")

    assert response.status_code == 500
    assert response.get_json()["error"] == "Erro interno"
