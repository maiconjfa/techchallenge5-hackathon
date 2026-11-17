"""Fixtures dos testes do ngo-service.

O `app.py` encerra o processo quando DATABASE_URL nao existe e cria um pool
real de conexoes no import. Para testar as rotas sem PostgreSQL, definimos
variaveis ficticias e substituimos o pool por um mock antes do import.
"""

import importlib
import os
import sys
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest

os.environ.setdefault("DATABASE_URL", "postgresql://test:test@localhost:5432/ngo_db")

SERVICE_ROOT = Path(__file__).resolve().parents[1]
if str(SERVICE_ROOT) not in sys.path:
    sys.path.insert(0, str(SERVICE_ROOT))


@pytest.fixture(scope="session")
def app_module():
    """Importa app.py com o pool de conexoes mockado."""
    with patch("psycopg2.pool.SimpleConnectionPool") as pool_class:
        pool_class.return_value = MagicMock(name="db-pool")
        module = importlib.import_module("app")
        yield module


@pytest.fixture(autouse=True)
def reset_pool(app_module):
    """Limpa chamadas registradas no pool entre os testes."""
    app_module.pool.reset_mock()


@pytest.fixture()
def client(app_module):
    """Test client do Flask."""
    return app_module.app.test_client()


@pytest.fixture()
def db_connection(app_module):
    """Conexao e cursor mockados, ja conectados ao pool do app."""
    cursor = MagicMock(name="cursor")
    cursor.__enter__.return_value = cursor
    cursor.__exit__.return_value = False

    connection = MagicMock(name="connection")
    connection.cursor.return_value = cursor

    app_module.pool.getconn.return_value = connection
    yield connection, cursor
    app_module.pool.putconn.assert_called_once_with(connection)
