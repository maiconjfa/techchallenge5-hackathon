package main

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestHealthHandler(t *testing.T) {
	app := &App{}
	req := httptest.NewRequest(http.MethodGet, "/health", nil)
	rec := httptest.NewRecorder()

	app.HealthHandler(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("status esperado %d, obtido %d", http.StatusOK, rec.Code)
	}
	if contentType := rec.Header().Get("Content-Type"); contentType != "application/json" {
		t.Errorf("Content-Type esperado application/json, obtido %q", contentType)
	}
	if body := rec.Body.String(); !strings.Contains(body, `"service":"donation-service"`) {
		t.Errorf("body inesperado: %s", body)
	}
}

func TestDonationHandlerRejectsInvalidJSON(t *testing.T) {
	app := &App{}
	req := httptest.NewRequest(http.MethodPost, "/donations", strings.NewReader("{invalido"))
	rec := httptest.NewRecorder()

	app.DonationHandler(rec, req)

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("status esperado %d, obtido %d", http.StatusBadRequest, rec.Code)
	}
}

func TestDonationHandlerRejectsUnsupportedMethod(t *testing.T) {
	app := &App{}
	req := httptest.NewRequest(http.MethodDelete, "/donations", nil)
	rec := httptest.NewRecorder()

	app.DonationHandler(rec, req)

	if rec.Code != http.StatusMethodNotAllowed {
		t.Fatalf("status esperado %d, obtido %d", http.StatusMethodNotAllowed, rec.Code)
	}
}
