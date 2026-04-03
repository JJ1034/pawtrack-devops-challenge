FROM golang:1.21-alpine AS builder
WORKDIR /app
COPY go.mod ./
COPY main.go ./
RUN CGO_ENABLED=0 GOOS=linux go build -o /pawtrack-api

FROM alpine:3.19
RUN apk --no-cache add ca-certificates
WORKDIR /
COPY --from=builder /pawtrack-api /pawtrack-api
EXPOSE 8080
CMD ["/pawtrack-api"]
