"""Fixtures dos testes do volunteer-service.

O `app.py` encerra o processo quando AWS_DYNAMODB_TABLE nao existe e cria um
resource real do DynamoDB no import. Para testar sem AWS, definimos variaveis
ficticias e substituimos o client boto3 por um mock antes do import.
"""

import importlib
import os
import sys
from pathlib import Path
from unittest.mock import MagicMock, patch

import boto3.dynamodb.conditions  # noqa: F401  (carrega boto3.dynamodb como no runtime)
import pytest

os.environ.setdefault("AWS_DYNAMODB_TABLE", "SolidaryTechVolunteers")
os.environ.setdefault("AWS_REGION", "us-east-1")

SERVICE_ROOT = Path(__file__).resolve().parents[1]
if str(SERVICE_ROOT) not in sys.path:
    sys.path.insert(0, str(SERVICE_ROOT))


@pytest.fixture(scope="session")
def app_module():
    """Importa app.py com o resource DynamoDB mockado."""
    with patch("boto3.resource") as resource:
        resource.return_value.Table.return_value = MagicMock(name="dynamodb-table")
        module = importlib.import_module("app")
        yield module


@pytest.fixture(autouse=True)
def reset_table(app_module):
    """Limpa chamadas registradas na tabela entre os testes."""
    app_module.table.reset_mock()


@pytest.fixture()
def client(app_module):
    """Test client do Flask."""
    return app_module.app.test_client()


@pytest.fixture()
def table(app_module):
    """Tabela DynamoDB mockada."""
    return app_module.table
