package main

import (
	"context"
	"log"
	"os"

	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/exporters/otlp/otlpmetric/otlpmetricgrpc"
	"go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc"
	"go.opentelemetry.io/otel/propagation"
	"go.opentelemetry.io/otel/sdk/metric"
	"go.opentelemetry.io/otel/sdk/resource"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
	semconv "go.opentelemetry.io/otel/semconv/v1.24.0"
)

// initTracer wires this service's traces AND metrics to the OTel
// Collector — never straight to any APM backend. Tracing pattern matches
// evaluation-service/otel.go; the metrics half is new (needed for the
// Requirement 4 alert rule, which needs a real http.server.request.duration
// metric with an http.status_code attribute to compute a 5xx rate from).
// otelhttp.NewHandler (main.go) picks up both providers automatically via
// otel.GetTracerProvider()/otel.GetMeterProvider() once they're set here —
// no changes needed to the handler-wrapping code itself.
func initTracer() func(context.Context) error {
	endpoint := os.Getenv("OTEL_EXPORTER_OTLP_ENDPOINT")
	if endpoint == "" {
		endpoint = "otel-collector-opentelemetry-collector.monitoring.svc.cluster.local:4317"
	}

	ctx := context.Background()

	res, err := resource.New(ctx,
		resource.WithAttributes(
			semconv.ServiceName("auth-service"),
		),
	)
	if err != nil {
		log.Fatalf("falha ao criar resource OTel: %v", err)
	}

	traceExporter, err := otlptracegrpc.New(ctx,
		otlptracegrpc.WithEndpoint(endpoint),
		otlptracegrpc.WithInsecure(),
	)
	if err != nil {
		log.Fatalf("falha ao criar exporter de traces OTLP: %v", err)
	}

	tp := sdktrace.NewTracerProvider(
		sdktrace.WithBatcher(traceExporter),
		sdktrace.WithResource(res),
	)
	otel.SetTracerProvider(tp)
	otel.SetTextMapPropagator(propagation.TraceContext{})

	metricExporter, err := otlpmetricgrpc.New(ctx,
		otlpmetricgrpc.WithEndpoint(endpoint),
		otlpmetricgrpc.WithInsecure(),
	)
	if err != nil {
		log.Fatalf("falha ao criar exporter de métricas OTLP: %v", err)
	}

	mp := metric.NewMeterProvider(
		metric.WithReader(metric.NewPeriodicReader(metricExporter)),
		metric.WithResource(res),
	)
	otel.SetMeterProvider(mp)

	log.Printf("OpenTelemetry (traces + métricas) inicializado, exportando para %s", endpoint)

	return func(ctx context.Context) error {
		if err := mp.Shutdown(ctx); err != nil {
			return err
		}
		return tp.Shutdown(ctx)
	}
}
