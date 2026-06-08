import connector_automator.utils;

import ballerina/io;
import ballerina/time;

public function executeSimpleConnectorGen(string... args) returns error? {
    if args.length() < 1 {
        printUsage();
        return;
    }

    string connectorPath = args[0];

    boolean quietMode = false;
    boolean autoYes = false;
    // Start from index 1 — args[0] is the connector path, not a flag.
    foreach string arg in args.slice(1) {
        if arg == "quiet" || arg == "--quiet" || arg == "-q" {
            quietMode = true;
        } else if arg == "yes" || arg == "--yes" || arg == "-y" {
            autoYes = true;
        }
    }

    printPlan(connectorPath, quietMode);

    if !quietMode {
        io:println("");
        io:println("Analyzing connector...");
    }

    ConnectorContext|error ctx = analyzeConnector(connectorPath);
    if ctx is error {
        io:println(string `✗ Connector analysis failed: ${ctx.message()}`);
        return ctx;
    }

    if !quietMode {
        io:println(string `✓ Analyzed connector: ${ctx.connectorOrg}/${ctx.connectorName}`);
        io:println(string `  Resource/remote methods in Client: ${ctx.resourceMethodCount}`);
        if ctx.isRepairMode {
            io:println("  Mode: connector.bal exists — repair (handled by code-fixer, skipping generation)");
        } else {
            io:println("  Mode: initial generation");
            if ctx.openApiSpecContent.length() > 0 {
                io:println("  OpenAPI spec: found");
            } else {
                io:println("  OpenAPI spec: not found (will infer from client.bal)");
            }
        }
    }

    if !quietMode {
        io:println("Initializing AI service...");
    }
    error? initResult = utils:initAIService(quietMode);
    if initResult is error {
        io:println(string `✗ AI initialization failed: ${initResult.message()}`);
        return error("AI service initialization failed: " + initResult.message());
    }

    if !quietMode {
        io:println("✓ AI service initialized");
    }

    time:Utc startTime = time:utcNow();

    if !quietMode {
        io:println("");
        io:println("Generating Connector client...");
    }

    GenerationResult|error genResult = generateConnectorClient(ctx, quietMode, autoYes);
    if genResult is error {
        io:println(string `✗ Generation failed: ${genResult.message()}`);
        return genResult;
    }

    decimal duration = time:utcDiffSeconds(time:utcNow(), startTime);
    printSummary(genResult, ctx, duration, quietMode);
}

function printPlan(string connectorPath, boolean quietMode) {
    if quietMode {
        return;
    }

    string sep = utils:createSeparator("=", 70);
    io:println(sep);
    io:println("Connector Client Generator");
    io:println(sep);
    io:println(string `Connector: ${connectorPath}`);
    io:println("");
    io:println("Steps:");
    io:println("  1. Analyze client.bal, types.bal, and OpenAPI spec");
    io:println("  2. Score and select operations via AI");
    io:println("  3. Generate connector.bal");
    io:println("  4. Validate compilation (run code-fixer if needed)");
    io:println(sep);
}

function printSummary(GenerationResult result, ConnectorContext ctx, decimal duration, boolean quietMode) {
    string sep = utils:createSeparator("=", 70);

    io:println("");
    io:println(sep);

    if ctx.isRepairMode {
        io:println("ℹ  Connector Client Generation Skipped");
        io:println(sep);
        io:println("");
        io:println("connector.bal already exists. Repair is handled by code-fixer.");
        io:println(string `Run: bal run -- openapi fix-code ${ctx.ballerinaPath}`);
    } else if result.success {
        io:println("✓ Connector Client Generated");
        io:println(sep);
        io:println("");
        io:println(string `Output  : ${result.connectorBalPath}`);
        io:println(string `Duration: ${duration}s`);
        if result.wasRepaired {
            io:println("Note    : Compilation errors were fixed by code-fixer");
        }
    } else {
        io:println("⚠  Connector Client Generation Partial");
        io:println(sep);
        io:println("");
        io:println(string `Output  : ${result.connectorBalPath}`);
        io:println(string `Duration: ${duration}s`);
        io:println("⚠  connector.bal was written but still has compilation errors");
        io:println("   Run: bal run -- openapi fix-code " + ctx.ballerinaPath);
    }

    if result.selectionReport.length() > 0 && !quietMode {
        io:println("");
        io:println("Selection Report:");
        io:println(result.selectionReport);
    }

    io:println("");
    io:println("Next Steps:");
    if ctx.isRepairMode {
        io:println("  • Fix compilation errors: bal run -- openapi fix-code <path>");
    } else if result.success {
        io:println("  • Review connector.bal and verify the selected operations");
        io:println("  • Generate examples: bal run -- openapi generate-examples <path>");
        io:println("  • Generate tests: bal run -- openapi generate-tests <path> <spec>");
    } else {
        io:println("  • Fix remaining errors: bal run -- openapi fix-code <path>");
        io:println("  • Review connector.bal manually if errors persist");
    }

    io:println(sep);
}

function printUsage() {
    io:println("Connector Client Generator");
    io:println("");
    io:println("USAGE");
    io:println("  bal run -- openapi generate-connector <connector-path> [options]");
    io:println("");
    io:println("OPTIONS");
    io:println("  yes      Auto-confirm all prompts");
    io:println("  quiet    Minimal logging output");
    io:println("");
    io:println("EXAMPLES");
    io:println("  bal run -- openapi generate-connector ./my-connector");
    io:println("  bal run -- openapi generate-connector ./my-connector yes quiet");
    io:println("");
    io:println("INPUTS");
    io:println("  <path>/ballerina/client.bal   (required)");
    io:println("  <path>/ballerina/types.bal    (required)");
    io:println("  <path>/docs/spec/aligned_ballerina_openapi.json  (preferred)");
    io:println("  <path>/openapi.yaml or openapi.json              (fallback)");
    io:println("");
    io:println("OUTPUT");
    io:println("  <path>/ballerina/connector.bal");
    io:println("");
    io:println("NOTES");
    io:println("  • If connector.bal already exists, generation is skipped.");
    io:println("    Use 'openapi fix-code' to repair an existing connector.bal.");
    io:println("  • Run after 'openapi generate-client' in the pipeline.");
    io:println("");
    io:println("ENVIRONMENT");
    io:println("  ANTHROPIC_API_KEY    Required for AI-powered generation");
    io:println("");
}
