package main

import (
	"context"
	"log"
	"os"

	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc"
	"go.opentelemetry.io/otel/propagation"
	"go.opentelemetry.io/otel/sdk/resource"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
	semconv "go.opentelemetry.io/otel/semconv/v1.24.0"
)

// initTracer wires this service's traces to the OTel Collector — never
// straight to any APM backend. The Collector (Fase04/CLAUDE.md Phase 2) is
// the single routing point for every telemetry signal; this service only
// needs to know how to speak OTLP.
func initTracer() func(context.Context) error {
	endpoint := os.Getenv("OTEL_EXPORTER_OTLP_ENDPOINT")
	if endpoint == "" {
		endpoint = "otel-collector-opentelemetry-collector.monitoring.svc.cluster.local:4317"
	}

	ctx := context.Background()

	exporter, err := otlptracegrpc.New(ctx,
		otlptracegrpc.WithEndpoint(endpoint),
		otlptracegrpc.WithInsecure(), // in-cluster traffic only, no TLS needed
	)
	if err != nil {
		log.Fatalf("falha ao criar exporter OTLP: %v", err)
	}

	res, err := resource.New(ctx,
		resource.WithAttributes(
			semconv.ServiceName("evaluation-service"),
		),
	)
	if err != nil {
		log.Fatalf("falha ao criar resource OTel: %v", err)
	}

	tp := sdktrace.NewTracerProvider(
		sdktrace.WithBatcher(exporter),
		sdktrace.WithResource(res),
	)
	otel.SetTracerProvider(tp)
	// W3C Trace Context propagator: this is what lets a downstream service
	// (flag-service, targeting-service) continue the SAME trace instead of
	// starting a disconnected one — it reads/writes the standard
	// "traceparent" HTTP header.
	otel.SetTextMapPropagator(propagation.TraceContext{})

	log.Printf("OpenTelemetry tracing inicializado, exportando para %s", endpoint)
	return tp.Shutdown
}
