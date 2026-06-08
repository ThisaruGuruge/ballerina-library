import connector_automator.code_fixer as fixer;
import connector_automator.utils;

import ballerina/file;
import ballerina/io;
import ballerina/lang.'string as strings;

const string SELECTION_REPORT_DELIMITER = "---SELECTION_REPORT---";
const string CONNECTOR_BAL_DELIMITER = "---CONNECTOR_BAL---";

// Retry limit for AI response parse failures. The AI is called again on each parse
// failure (missing delimiters, truncated response) up to this limit before giving up.
const int MAX_GEN_RETRIES = 3;

// Output token budget for connector.bal generation.
//
// Budget breakdown (worst-case 15-operation connector):
//   connector.bal body : 15 ops × ~30 lines + overhead (license, AuthConfig, helpers, class)
//                      ≈ 600 lines × 40 chars ÷ 3.5 chars/token ≈ 6 860 tokens
//   selection report   : ~200 lines × 45 chars ÷ 3.5 chars/token ≈ 2 570 tokens
//   total estimated    : ~9 430 tokens
//   16 000 provides ~70 % headroom for verbose doc-comments, many helper functions,
//   and large scoring tables — while staying within the model's extended-output limit.
const int MAX_OUTPUT_TOKENS = 16000;

function generateConnectorClient(ConnectorContext ctx, boolean quietMode, boolean autoYes)
        returns GenerationResult|error {

    string connectorBalPath = ctx.ballerinaPath + "/connector.bal";

    if ctx.isRepairMode {
        if !quietMode {
            io:println("  ℹ  connector.bal already exists — repair is handled by code-fixer");
            io:println("     Run: bal run -- openapi fix-code " + ctx.connectorPath);
        }
        return {
            success: true,
            connectorBalPath,
            selectionReport: "",
            wasRepaired: false
        };
    }

    // Stage 1: AI generation (with retry on parse failure)
    if !quietMode {
        io:println("  Calling AI to score operations and generate connector.bal...");
    }

    string systemPrompt = getGenerationSystemPrompt();
    string userPrompt = getInitialGenerationUserPrompt(ctx);

    string selectionReport = "";
    string connectorBal = "";
    boolean parseSucceeded = false;
    string lastParseErrorMsg = "";

    int attempt = 1;
    while attempt <= MAX_GEN_RETRIES {
        string|error aiResult = utils:callAIAdvanced(userPrompt, systemPrompt, MAX_OUTPUT_TOKENS);
        if aiResult is error {
            return error("AI generation failed: " + aiResult.message());
        }

        [string, string]|error parsedResult = parseAIResponse(aiResult);
        if parsedResult is [string, string] {
            selectionReport = parsedResult[0];
            connectorBal = parsedResult[1];
            parseSucceeded = true;
            break;
        }

        lastParseErrorMsg = parsedResult.message();
        if !quietMode {
            io:println(string `  ⚠  AI response parse failed (attempt ${attempt}/${MAX_GEN_RETRIES}): ${lastParseErrorMsg}`);
            if attempt < MAX_GEN_RETRIES {
                io:println("  Retrying...");
            }
        }
        attempt += 1;
    }

    if !parseSucceeded {
        return error(string `Failed to parse AI response after ${MAX_GEN_RETRIES} attempts: ${lastParseErrorMsg}`);
    }

    if connectorBal.trim().length() == 0 {
        return error("AI returned empty connector.bal content");
    }

    // Write connector.bal
    error? writeResult = io:fileWriteString(connectorBalPath, connectorBal);
    if writeResult is error {
        return error("Failed to write connector.bal: " + writeResult.message());
    }

    if !quietMode {
        io:println("  ✓ connector.bal written");
    }

    // Persist the selection report alongside the connector for human review and audit trail
    if selectionReport.length() > 0 {
        string reportPath = ctx.connectorPath + "/docs/spec/connector_selection.md";
        boolean docsSpecExists = check file:test(ctx.connectorPath + "/docs/spec", file:EXISTS);
        if docsSpecExists {
            error? reportWrite = io:fileWriteString(reportPath, selectionReport);
            if reportWrite is error {
                if !quietMode {
                    io:println("  ⚠  Could not save selection report: " + reportWrite.message());
                }
            } else if !quietMode {
                io:println(string `  ✓ Selection report saved to ${reportPath}`);
            }
        }
    }

    // Stage 2: Build validation
    if !quietMode {
        io:println("  Validating compilation...");
    }

    utils:CommandResult buildResult = utils:executeBalBuild(ctx.ballerinaPath, quietMode);

    if !utils:hasCompilationErrors(buildResult) {
        if !quietMode {
            io:println("  ✓ Compilation successful");
        }
        return {
            success: true,
            connectorBalPath,
            selectionReport,
            wasRepaired: false
        };
    }

    // Stage 3: code_fixer for any compilation errors introduced by generated code
    if !quietMode {
        io:println("  ⚠  Compilation errors found — running code-fixer...");
    }

    fixer:FixResult|fixer:BallerinaFixerError fixResult = fixer:fixAllErrors(
        ctx.ballerinaPath, quietMode, autoYes);

    boolean fixSucceeded = false;
    if fixResult is fixer:FixResult {
        utils:CommandResult retryBuild = utils:executeBalBuild(ctx.ballerinaPath, true);
        fixSucceeded = !utils:hasCompilationErrors(retryBuild);
        if !quietMode {
            if fixSucceeded {
                io:println("  ✓ Compilation errors resolved by code-fixer");
            } else {
                io:println(string `  ⚠  ${fixResult.errorsRemaining} error(s) remain after fixing`);
            }
        }
    } else if !quietMode {
        io:println("  ⚠  code-fixer encountered an issue: " + fixResult.message());
    }

    return {
        success: fixSucceeded,
        connectorBalPath,
        selectionReport,
        wasRepaired: true
    };
}

function parseAIResponse(string response) returns [string, string]|error {
    int? reportIdx = response.indexOf(SELECTION_REPORT_DELIMITER);
    int? connectorIdx = response.indexOf(CONNECTOR_BAL_DELIMITER);

    if reportIdx is () {
        return error("Response missing ---SELECTION_REPORT--- delimiter");
    }
    if connectorIdx is () {
        return error("Response missing ---CONNECTOR_BAL--- delimiter");
    }

    int reportContentStart = <int>reportIdx + SELECTION_REPORT_DELIMITER.length();
    string selectionReport = strings:trim(response.substring(reportContentStart, <int>connectorIdx));

    int connectorContentStart = <int>connectorIdx + CONNECTOR_BAL_DELIMITER.length();
    string connectorBal = strings:trim(response.substring(connectorContentStart));

    connectorBal = stripCodeFence(connectorBal);

    return [selectionReport, connectorBal];
}

function stripCodeFence(string content) returns string {
    string result = content;

    if result.startsWith("```") {
        int? newline = result.indexOf("\n");
        if newline is int {
            result = result.substring(newline + 1);
        }
    }

    if result.endsWith("```") {
        result = strings:trim(result.substring(0, result.length() - 3));
    }

    return result;
}
