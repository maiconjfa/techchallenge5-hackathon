"""Testes unitarios das rotas do ngo-service (sem banco de dados real)."""

import psycopg2

NGO_PAYLOAD = {
    "name": "ONG Exemplo",
    "email": "contato@ongexemplo.org",
    "cause": "educacao",
    "city": "Sao Paulo",
}


def test_health_returns_service_status(client):
    response = client.get("/health")

    assert response.status_code == 200
    assert response.get_json() == {"status": "ok", "service": "ngo-service"}


def test_create_ngo_rejects_missing_fields(client):
    response = client.post("/ngos", json={"name": "ONG Incompleta"})

    assert response.status_code == 400
    assert response.get_json()["error"] == "Campos obrigatórios ausentes"


def test_create_ngo_persists_and_returns_201(client, db_connection):
    connection, cursor = db_connection
    cursor.fetchone.return_value = {"id": 1, **NGO_PAYLOAD}

    response = client.post("/ngos", json=NGO_PAYLOAD)

    assert response.status_code == 201
    assert response.get_json()["id"] == 1
    assert response.get_json()["name"] == NGO_PAYLOAD["name"]
    cursor.execute.assert_called_once()
    connection.commit.assert_called_once()


def test_create_ngo_returns_409_on_duplicate_email(client, db_connection):
    connection, cursor = db_connection
    cursor.execute.side_effect = psycopg2.IntegrityError("email duplicado")

    response = client.post("/ngos", json=NGO_PAYLOAD)

    assert response.status_code == 409
    assert response.get_json()["error"] == "E-mail já cadastrado"
    connection.rollback.assert_called_once()


def test_create_ngo_returns_500_on_unexpected_error(client, db_connection):
    connection, cursor = db_connection
    cursor.execute.side_effect = RuntimeError("falha inesperada")

    response = client.post("/ngos", json=NGO_PAYLOAD)

    assert response.status_code == 500
    assert response.get_json()["error"] == "Erro interno"
    connection.rollback.assert_called_once()


def test_list_ngos_returns_rows(client, db_connection):
    _, cursor = db_connection
    cursor.fetchall.return_value = [
        {"id": 2, **NGO_PAYLOAD},
        {"id": 1, **NGO_PAYLOAD},
    ]

    response = client.get("/ngos")

    assert response.status_code == 200
    assert len(response.get_json()) == 2
    cursor.execute.assert_called_once()


def test_list_ngos_returns_500_on_database_error(client, db_connection):
    _, cursor = db_connection
    cursor.execute.side_effect = RuntimeError("conexao perdida")

    response = client.get("/ngos")

    assert response.status_code == 500
    assert response.get_json()["error"] == "Erro interno"
