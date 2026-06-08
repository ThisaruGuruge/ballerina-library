import ballerina/file;
import ballerina/io;
import ballerina/lang.'string as strings;
import ballerina/lang.regexp;

public function analyzeConnector(string connectorPath) returns ConnectorContext|error {
    string ballerinaPath = connectorPath + "/ballerina";

    // Read Ballerina.toml for org/name
    string connectorOrg = "generated";
    string connectorName = "connector";
    string|io:Error tomlContent = io:fileReadString(ballerinaPath + "/Ballerina.toml");
    if tomlContent is string {
        [connectorOrg, connectorName] = extractOrgAndName(tomlContent);
    }

    // Read client.bal (required)
    string clientBalContent = check io:fileReadString(ballerinaPath + "/client.bal");

    // Read types.bal (required)
    string typesBalContent = check io:fileReadString(ballerinaPath + "/types.bal");

    // Find OpenAPI spec (optional — connector.bal can still be generated without it)
    string openApiSpecContent = "";
    string|error specResult = findAndReadOpenApiSpec(connectorPath);
    if specResult is string {
        openApiSpecContent = specResult;
    }

    // Check for existing connector.bal
    string connectorBalPath = ballerinaPath + "/connector.bal";
    boolean connectorExists = check file:test(connectorBalPath, file:EXISTS);
    string connectorBalContent = "";
    if connectorExists {
        connectorBalContent = check io:fileReadString(connectorBalPath);
    }

    return {
        connectorPath,
        ballerinaPath,
        clientBalContent,
        typesBalContent,
        openApiSpecContent,
        connectorBalContent,
        isRepairMode: connectorExists,
        resourceMethodCount: countMethods(clientBalContent),
        connectorOrg,
        connectorName
    };
}

function findAndReadOpenApiSpec(string connectorPath) returns string|error {
    string[] candidates = [
        connectorPath + "/docs/spec/aligned_ballerina_openapi.json",
        connectorPath + "/openapi.yaml",
        connectorPath + "/openapi.json",
        connectorPath + "/ballerina/openapi.yaml",
        connectorPath + "/ballerina/openapi.json"
    ];

    foreach string path in candidates {
        boolean exists = check file:test(path, file:EXISTS);
        if exists {
            return check io:fileReadString(path);
        }
    }

    return error("OpenAPI specification not found in " + connectorPath);
}

function extractOrgAndName(string tomlContent) returns [string, string] {
    string org = "generated";
    string name = "connector";
    boolean inPackageSection = false;

    string[] lines = regexp:split(re `\n`, tomlContent);
    foreach string line in lines {
        string trimmed = strings:trim(line);
        if trimmed == "[package]" {
            inPackageSection = true;
            continue;
        }
        if trimmed.startsWith("[") && trimmed != "[package]" {
            inPackageSection = false;
            continue;
        }
        if !inPackageSection {
            continue;
        }
        int? eqIdx = trimmed.indexOf("=");
        if eqIdx is int {
            string key = strings:trim(trimmed.substring(0, eqIdx));
            string rawVal = strings:trim(trimmed.substring(eqIdx + 1));
            string val = strings:trim(regexp:replaceAll(re `"`, rawVal, ""));
            if key == "org" {
                org = val;
            } else if key == "name" {
                name = val;
            }
        }
    }

    return [org, name];
}

function countMethods(string clientContent) returns int {
    regexp:Span[] resource = (re `resource\s+isolated\s+function`).findAll(clientContent);
    regexp:Span[] remote = (re `remote\s+isolated\s+function`).findAll(clientContent);
    return resource.length() + remote.length();
}
