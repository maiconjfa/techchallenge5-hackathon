FROM golang:1.27-alpine AS builder

WORKDIR /src

COPY go.mod go.sum ./
RUN go mod download

COPY main.go ./
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o /donation-service .

FROM alpine:3.20

RUN apk add --no-cache ca-certificates && \
    adduser -D -u 1000 app

COPY --from=builder /donation-service /usr/local/bin/donation-service

USER app

EXPOSE 8082

HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD wget -qO- http://localhost:8082/health > /dev/null || exit 1

CMD ["/usr/local/bin/donation-service"]
