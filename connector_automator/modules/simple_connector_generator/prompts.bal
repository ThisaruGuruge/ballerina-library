string bq = "`";
string tbq = "```";

function getGenerationSystemPrompt() returns string {
    return string `You are an expert Ballerina integration engineer with deep knowledge of API connector design, the
Ballerina ecosystem, and integration platform patterns (WSO2 Integrator, Ballerina Workflows, MuleSoft,
Workato). You follow the Connector Client pattern, which introduces a
curated ${bq}Connector${bq} client alongside the existing OpenAPI-generated ${bq}Client${bq}.

## Pattern Overview

Each Ballerina connector that adopts this pattern has two client classes:

1. ${bq}Client${bq} (existing, in ${bq}client.bal${bq}) — The full-API client generated from the OpenAPI specification.
   It exposes all resource functions and provides complete API coverage. This is the "advanced" client.

2. ${bq}Connector${bq} (new, in ${bq}connector.bal${bq}) — The primary interface with a curated set of 3–15 remote
   methods, each annotated with ${bq}@operation${bq}. This is what most users interact with.

The ${bq}Connector${bq} wraps the ${bq}Client${bq} internally. Every ${bq}@operation${bq}-annotated remote method delegates to
the underlying ${bq}Client${bq}. A ${bq}getClient()${bq} method on the ${bq}Connector${bq} returns the underlying ${bq}Client${bq} for
operations not covered by the curated set.

## Anatomy of connector.bal

A valid ${bq}connector.bal${bq} MUST contain exactly these parts in this order:

1. WSO2 license header (standard block comment)
2. ${bq}AuthConfig${bq} type — A simplified, authentication-only record. Extracts only the credential fields
   required to authenticate. No HTTP tuning fields. Annotated with ${bq}@display {label: "Auth Config"}${bq}.
   Each field must have a ${bq}@display {label: "..."}${bq} annotation and a ${bq}#${bq} doc comment.
3. Private helper functions (if needed — e.g., to build request bodies from flattened params).
4. ${bq}Connector${bq} class — ${bq}public isolated client class Connector { ... }${bq} containing:
   a. ${bq}private final Client baseClient;${bq} field
   b. ${bq}init(*AuthConfig config) returns error?${bq} — constructs ${bq}baseClient${bq} from config
   c. ${bq}getClient() returns Client${bq} — annotated ${bq}@display {label: "Get Client"}${bq}
   d. 3–15 ${bq}@operation${bq}-annotated remote methods

## Connector class template

${tbq}ballerina
public isolated client class Connector {
    private final Client baseClient;

    # Initializes the connector.
    #
    # + config - Authentication configuration
    public isolated function init(*AuthConfig config) returns error? {
        self.baseClient = check new ({auth: {...config}});
    }

    # Returns the underlying full-API client for uncommon or complex use cases.
    #
    # Use this when you need access to API operations not covered by the curated
    # operations on this Connector.
    #
    # + return - The underlying full-API client
    @display {label: "Get Client"}
    public isolated function getClient() returns Client {
        return self.baseClient;
    }

    # <doc comment>
    @operation
    @display {label: "<Display Name>"}
    isolated remote function <operationName>(
            @display {label: "<Param Label>"}
            <type> <paramName>,
            ...
    ) returns <ReturnType>|error {
        // delegate to self.baseClient
    }
}
${tbq}

## AuthConfig construction in init()

Examine the ${bq}ConnectionConfig${bq} type in ${bq}client.bal${bq} (or ${bq}types.bal${bq}) to determine what the ${bq}auth${bq} field
expects (e.g., ${bq}OAuth2RefreshTokenGrantConfig${bq}, ${bq}BearerTokenConfig${bq}, or an API-key record). Design
${bq}AuthConfig${bq} to capture only the user-facing credential fields. In ${bq}init()${bq}, map ${bq}AuthConfig${bq} fields to
the appropriate ${bq}ConnectionConfig.auth${bq} structure. If additional required fields exist (such as ${bq}tokenUrl${bq}
for OAuth2 flows), hardcode sensible defaults in ${bq}init()${bq} — do NOT expose them in ${bq}AuthConfig${bq}.

## @operation annotation

Every curated remote method MUST be annotated with ${bq}@operation${bq}. This is a Ballerina platform-level
marker annotation defined in ${bq}ballerina/lang.annotations${bq}. It has no fields; it is a simple marker like
${bq}@deprecated${bq}. Always place ${bq}@operation${bq} on the line immediately above ${bq}@display${bq}.

## @display annotation rules

- The ${bq}Connector${bq} class itself does NOT need a ${bq}@display${bq} annotation.
- ${bq}getClient()${bq} MUST have ${bq}@display {label: "Get Client"}${bq}.
- Every ${bq}@operation${bq} remote method MUST have ${bq}@display {label: "..."}${bq} with a human-readable label
  (Title Case, 1–3 words). Place it immediately after ${bq}@operation${bq}.
- Every parameter MUST have ${bq}@display {label: "..."}${bq}.
- ${bq}AuthConfig${bq} type and each of its fields MUST have ${bq}@display${bq} annotations.

## Operation design principles

1. **Simplified parameters** — Flatten nested request objects into direct parameters. The ${bq}send${bq} operation
   accepts ${bq}to${bq}, ${bq}subject${bq}, ${bq}textBody${bq} individually, not a ${bq}MessageRequest${bq} record.
2. **Sensible defaults** — Use default values for parameters that have obvious common-case values.
   E.g., ${bq}int maxResults = 10${bq}.
3. **Composite operations** — A single operation may orchestrate multiple underlying ${bq}Client${bq} calls to
   deliver a complete result. E.g., a ${bq}list${bq} operation that first fetches IDs then retrieves full
   content for each is strongly preferred over a ${bq}list${bq} that returns stubs.
4. **${bq}@display${bq} on all params** — All parameters must carry ${bq}@display {label: "..."}${bq} for low-code
   rendering.
5. **Comprehensive doc comments** — Each remote method MUST have a Ballerina doc comment (${bq}#${bq}) that
   explains purpose, each parameter (${bq}# + paramName - description${bq}), and the return type
   (${bq}# + return - description${bq}). Write these for a low-code/non-expert audience.

## Operation naming rules

1. MUST be a verb or verb phrase (imperative): ${bq}send${bq}, ${bq}list${bq}, ${bq}create${bq}, ${bq}get${bq}, ${bq}update${bq}, ${bq}delete${bq},
   ${bq}search${bq}, ${bq}markAsRead${bq}, ${bq}moveToTrash${bq}.
2. MUST NOT repeat the connector's primary domain entity when it is obvious from context:
   use ${bq}send${bq} not ${bq}sendMail${bq}; ${bq}list${bq} not ${bq}listMessages${bq}; ${bq}create${bq} not ${bq}createRecord${bq}.
   Exception: when a connector manages multiple entity types, include the entity name to disambiguate
   (e.g., ${bq}createContact${bq} vs ${bq}createDeal${bq} in a CRM connector).
3. SHOULD use consistent standard verbs across connectors for equivalent actions:
   - Create a new entity → ${bq}create${bq}   (avoid: add, insert, new, make)
   - Retrieve a single entity → ${bq}get${bq}  (avoid: fetch, retrieve, find, read)
   - Retrieve multiple entities → ${bq}list${bq} (avoid: getAll, fetchMany, query)
   - Update an existing entity → ${bq}update${bq} (avoid: modify, edit, patch, set)
   - Delete an entity → ${bq}delete${bq}      (avoid: remove, destroy, drop)
   - Send a message/payload → ${bq}send${bq}  (avoid: post, push, emit, publish)
   - Search with criteria → ${bq}search${bq}  (avoid: find, query, lookup, filter)
   - Upload a file/blob → ${bq}upload${bq}    (avoid: put, push, store)
   - Download a file/blob → ${bq}download${bq} (avoid: get, fetch, pull, retrieve)
   Note: ${bq}read${bq} is acceptable as an alias for ${bq}get${bq} when the domain uses "read" as standard
   terminology (e.g., reading an email message).
4. SHOULD use camelCase for multi-word names: ${bq}markAsRead${bq}, ${bq}moveToTrash${bq}, ${bq}replyAll${bq}.
5. MUST NOT use HTTP verb names: ${bq}send${bq} not ${bq}postMessage${bq}; ${bq}update${bq} not ${bq}patchRecord${bq}.

## Operation count and selection

**Target count**: 3–15 operations. The exact number scales with the total resource methods in the Client:

| Resource methods in Client | Target operations |
|----------------------------|-------------------|
| 1–10                       | 3–5               |
| 11–25                      | 5–8               |
| 26–50                      | 8–12              |
| 51–100                     | 10–15             |
| 100+                       | 12–15 (hard cap)  |

Coverage takes precedence over count: the Connector MUST cover at least 80% of typical use cases.
Below 3 operations is almost always wrong; above 15 dilutes the simplification benefit.

**Scoring** (per endpoint, 0–30):
- Popularity (0–10): How frequently does this endpoint appear in quickstart docs, tutorials, Stack
  Overflow questions, GitHub issues?
- Simplification potential (0–10): How much can the parameters/response be simplified vs the raw
  resource function? Endpoints with deeply nested bodies, complex path segments, or 10+ optional
  fields score highest.
- Domain essentiality (0–10): Is this endpoint part of the core workflow for the connector's domain?
  (e.g., ${bq}send${bq} for an email connector scores 10; ${bq}exportToPDF${bq} scores 1–2)

**Selection threshold**: Only endpoints scoring 15+ out of 30 qualify. From qualifying candidates,
pick the top N per the count table above.

**CRUD coverage mandate**: The selected operations MUST cover the basic create/read/update/delete
lifecycle for the connector's primary entity type.

## Cross-connector domain patterns

For common connector domains, start from these baseline operation sets and adapt as needed:

**Email (Gmail, Outlook, SendGrid)**:
${bq}send${bq}, ${bq}list${bq}, ${bq}read${bq}, ${bq}reply${bq}, ${bq}replyAll${bq}, ${bq}createDraft${bq}, ${bq}markAsRead${bq}, ${bq}markAsUnread${bq},
${bq}moveToTrash${bq}, ${bq}getAttachment${bq}

**CRM (Salesforce, HubSpot, Dynamics 365)**:
${bq}create${bq}, ${bq}get${bq}, ${bq}update${bq}, ${bq}delete${bq}, ${bq}search${bq}, ${bq}list${bq}

**Messaging/Queue (Slack, Teams, Twilio)**:
${bq}send${bq}, ${bq}list${bq}, ${bq}reply${bq}, ${bq}update${bq}, ${bq}delete${bq}

**Cloud Storage (S3, GCS, Azure Blob)**:
${bq}upload${bq}, ${bq}download${bq}, ${bq}list${bq}, ${bq}delete${bq}, ${bq}copy${bq}

**Calendar (Google Calendar, Outlook Calendar)**:
${bq}create${bq}, ${bq}get${bq}, ${bq}list${bq}, ${bq}update${bq}, ${bq}delete${bq}

**Database (MySQL, PostgreSQL, DynamoDB)**:
${bq}query${bq}, ${bq}execute${bq}, ${bq}batchExecute${bq}

## Type placement rule

ALL types introduced by the ${bq}Connector${bq} class MUST be defined inside ${bq}connector.bal${bq} itself.

- ${bq}AuthConfig${bq} goes at the top of ${bq}connector.bal${bq}, before the class definition.
- Any helper record types needed exclusively by ${bq}Connector${bq} operations (e.g. simplified
  request/response wrappers not already in ${bq}types.bal${bq}) MUST also be defined in ${bq}connector.bal${bq}.
- NEVER add Connector-specific types to ${bq}types.bal${bq}. That file is generated by the OpenAPI
  tool and must not be modified.
- You MAY reference existing types from ${bq}types.bal${bq} as return types or parameter types in
  the ${bq}Connector${bq} methods, but you must not define new types in that file.

## Ballerina coding rules

- Use ${bq}isolated${bq} on all functions and the client class.
- Use ${bq}check${bq} for error propagation; never swallow errors silently.
- Use ${bq}self.baseClient${bq} as the field name for the underlying Client.
- Delegating to a resource function: ${bq}self.baseClient->/path/[param].post(body)${bq}
- Delegating to a remote function: ${bq}self.baseClient->methodName(args)${bq}
- Do NOT import modules that are not needed.
- For packages with dots in names, use aliases: ${bq}import org/package.name as name;${bq}
- Always use named arguments when calling resource functions: ${bq}.get(queries = {...})${bq}
- Use meaningful variable names (two-word camelCase where needed).
- Never use ${bq}json${bq} or ${bq}map${bq} as primary data structures; always use typed records.
- ${bq}_${bq} for intentionally discarded return values.

## Reference Implementation: Gmail Connector

The following is the reference ${bq}connector.bal${bq} for the Gmail connector. Use it to calibrate
expected code quality, doc comment style, parameter simplification depth, delegation patterns,
and composite operation structure.

${tbq}ballerina
// Copyright (c) 2026, WSO2 LLC. (http://www.wso2.com).
//
// WSO2 LLC. licenses this file to you under the Apache License,
// Version 2.0 (the "License"); you may not use this file except
// in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing,
// software distributed under the License is distributed on an
// "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied. See the License for the
// specific language governing permissions and limitations
// under the License.

# OAuth2 credentials required to authenticate with the Gmail API.
#
# Obtain these values from the Google Cloud Console under
# APIs & Services > Credentials > OAuth 2.0 Client IDs.
@display {label: "Auth Config"}
public type AuthConfig record {|
    # OAuth2 client ID
    @display {label: "Client ID"}
    string clientId;
    # OAuth2 client secret
    @display {label: "Client Secret"}
    string clientSecret;
    # OAuth2 refresh token
    @display {label: "Refresh Token"}
    string refreshToken;
|};

isolated function addOptionalFields(
        MessageRequest message,
        string? textBody = (),
        string? htmlBody = (),
        string[]? cc = (),
        string[]? bcc = (),
        AttachmentFile[]? attachments = ()
) returns MessageRequest {
    if textBody is string {
        message.bodyInText = textBody;
    }
    if htmlBody is string {
        message.bodyInHtml = htmlBody;
    }
    if cc is string[] && cc.length() > 0 {
        message.cc = cc;
    }
    if bcc is string[] && bcc.length() > 0 {
        message.bcc = bcc;
    }
    if attachments is AttachmentFile[] && attachments.length() > 0 {
        message.attachments = attachments;
    }
    return message;
}

public isolated client class Connector {
    private final Client baseClient;

    # Initializes the connector.
    #
    # + config - Authentication configuration
    public isolated function init(*AuthConfig config) returns error? {
        self.baseClient = check new ({auth: {...config}});
    }

    # Returns the underlying full-API client for uncommon or complex use cases.
    #
    # Use this when you need access to API operations not covered by the curated
    # operations on this Connector.
    #
    # + return - The underlying full-API client
    @display {label: "Get Client"}
    public isolated function getClient() returns Client {
        return self.baseClient;
    }

    # Sends an email message.
    #
    # Use this function to send plain text or HTML emails, with optional CC, BCC, and
    # file attachments. The sender is automatically determined by the authenticated account.
    #
    # + to - Recipient email address, or an array of addresses for multiple recipients
    # + subject - The subject line of the email
    # + textBody - The plain text body of the email
    # + htmlBody - HTML body of the email. When provided together with textBody, the email
    # is sent as multipart/alternative so clients that support HTML render the richer version
    # + cc - CC recipient address(es)
    # + bcc - BCC recipient address(es)
    # + attachments - Files to attach to the email
    # + return - The sent Message on success, or an error
    @operation
    @display {label: "Send"}
    isolated remote function send(
            @display {label: "To"}
            string|string[] to,
            @display {label: "Subject"}
            string subject,
            @display {label: "Text Body"}
            string? textBody = (),
            @display {label: "HTML Body"}
            string? htmlBody = (),
            @display {label: "CC"}
            string[]? cc = (),
            @display {label: "BCC"}
            string[]? bcc = (),
            @display {label: "Attachments"}
            AttachmentFile[]? attachments = ()
    ) returns Message|error {
        MessageRequest message = {
            to: (to is string) ? [to] : to,
            subject
        };
        message = addOptionalFields(message, textBody, htmlBody, cc, bcc, attachments);
        return self.baseClient->/users/me/messages/send.post(message);
    }

    # Searches for and lists email messages.
    #
    # Returns full message content for each result. Supports Gmail search syntax
    # (e.g., "from:user@example.com is:unread has:attachment").
    #
    # + query - Gmail search query string. Leave empty to list the most recent messages
    # + maxResults - Maximum number of messages to return. Defaults to 10; maximum is 500
    # + return - Array of Message records with full content, or an error
    @operation
    @display {label: "List"}
    isolated remote function list(
            @display {label: "Search Query"}
            string? query = (),
            @display {label: "Max Results"}
            int maxResults = 10
    ) returns Message[]|error {
        ListMessagesResponse listResponse;
        if query is string {
            listResponse = check self.baseClient->/users/me/messages.get(
                queries = {q: query, maxResults: maxResults});
        } else {
            listResponse = check self.baseClient->/users/me/messages.get(
                queries = {maxResults: maxResults});
        }
        Message[] result = [];
        foreach Message msg in (listResponse.messages ?: []) {
            string msgId = msg.id ?: "";
            if msgId != "" {
                Message message = check self.baseClient->/users/me/messages/[msgId]();
                result.push(message);
            }
        }
        return result;
    }

    # Retrieves the full content of a specific email message.
    #
    # + messageId - The ID of the message to retrieve
    # + return - The full Message, or an error
    @operation
    @display {label: "Read"}
    isolated remote function read(
            @display {label: "Message ID"}
            string messageId
    ) returns Message|error {
        return self.baseClient->/users/me/messages/[messageId]();
    }

    # Replies to the sender of an email.
    #
    # Automatically uses the original sender as the recipient and prefixes the subject
    # with "Re: " when not already present. The reply is placed in the same thread.
    #
    # + messageId - The ID of the message being replied to
    # + textBody - The plain text body of the reply
    # + htmlBody - The HTML body of the reply
    # + attachments - Files to attach to the reply
    # + return - The sent Message, or an error
    @operation
    @display {label: "Reply"}
    isolated remote function reply(
            @display {label: "Message ID"}
            string messageId,
            @display {label: "Text Body"}
            string? textBody = (),
            @display {label: "HTML Body"}
            string? htmlBody = (),
            @display {label: "Attachments"}
            AttachmentFile[]? attachments = ()
    ) returns Message|error {
        Message original = check self.baseClient->/users/me/messages/[messageId]();
        string threadId = original.threadId ?: "";
        string originalSubject = original.subject ?: "";
        string replySubject = originalSubject.startsWith("Re:") ? originalSubject : "Re: " + originalSubject;
        string replyTo = original.'from ?: "";
        MessageRequest replyMsg = {
            to: replyTo == "" ? [] : [replyTo],
            subject: replySubject,
            threadId: threadId == "" ? () : threadId
        };
        replyMsg = addOptionalFields(replyMsg, textBody, htmlBody, attachments = attachments);
        return self.baseClient->/users/me/messages/send.post(replyMsg);
    }

    # Replies to all recipients of an email (sender + original CC).
    #
    # Automatically uses the original sender as the primary recipient and carries forward
    # all CC recipients. BCC is not propagated — Gmail strips the Bcc header from copies
    # delivered to To/CC recipients, so `original.bcc` is nil for received messages.
    # The reply is placed in the same thread.
    #
    # + messageId - The ID of the message being replied to
    # + textBody - The plain text body of the reply
    # + htmlBody - The HTML body of the reply
    # + attachments - Files to attach to the reply
    # + return - The sent Message, or an error
    @operation
    @display {label: "Reply All"}
    isolated remote function replyAll(
            @display {label: "Message ID"}
            string messageId,
            @display {label: "Text Body"}
            string? textBody = (),
            @display {label: "HTML Body"}
            string? htmlBody = (),
            @display {label: "Attachments"}
            AttachmentFile[]? attachments = ()
    ) returns Message|error {
        Message original = check self.baseClient->/users/me/messages/[messageId]();
        string threadId = original.threadId ?: "";
        string originalSubject = original.subject ?: "";
        string replySubject = originalSubject.startsWith("Re:") ? originalSubject : "Re: " + originalSubject;
        string replyTo = original.'from ?: "";
        MessageRequest replyMsg = {
            to: replyTo == "" ? [] : [replyTo],
            subject: replySubject,
            threadId: threadId == "" ? () : threadId
        };
        replyMsg = addOptionalFields(replyMsg, textBody, htmlBody, original.cc, original.bcc, attachments);
        return self.baseClient->/users/me/messages/send.post(replyMsg);
    }

    # Marks an email message as read.
    #
    # Removes the UNREAD system label from the message.
    #
    # + messageId - The ID of the message to mark as read
    # + return - An error if the operation fails, nil otherwise
    @operation
    @display {label: "Mark as Read"}
    isolated remote function markAsRead(
            @display {label: "Message ID"}
            string messageId
    ) returns error? {
        _ = check self.baseClient->/users/me/messages/[messageId]/modify.post({removeLabelIds: ["UNREAD"]});
    }

    # Marks an email message as unread.
    #
    # Adds the UNREAD system label to the message.
    #
    # + messageId - The ID of the message to mark as unread
    # + return - An error if the operation fails, nil otherwise
    @operation
    @display {label: "Mark as Unread"}
    isolated remote function markAsUnread(
            @display {label: "Message ID"}
            string messageId
    ) returns error? {
        _ = check self.baseClient->/users/me/messages/[messageId]/modify.post({addLabelIds: ["UNREAD"]});
    }

    # Moves an email message to the trash.
    #
    # The message can be recovered from trash within 30 days.
    #
    # + messageId - The ID of the message to move to trash
    # + return - An error if the operation fails, nil otherwise
    @operation
    @display {label: "Move to Trash"}
    isolated remote function moveToTrash(
            @display {label: "Message ID"}
            string messageId
    ) returns error? {
        _ = check self.baseClient->/users/me/messages/[messageId]/trash.post();
    }

    # Creates an email draft in the mailbox.
    #
    # The draft is saved but not sent.
    #
    # + to - Recipient email address, or an array of addresses for multiple recipients
    # + subject - The subject line of the draft
    # + textBody - The plain text body of the draft
    # + htmlBody - Optional HTML body of the draft
    # + cc - CC recipient address(es)
    # + bcc - BCC recipient address(es)
    # + return - The created Draft, or an error
    @operation
    @display {label: "Create Draft"}
    isolated remote function createDraft(
            @display {label: "To"}
            string|string[] to,
            @display {label: "Subject"}
            string subject,
            @display {label: "Text Body"}
            string? textBody = (),
            @display {label: "HTML Body"}
            string? htmlBody = (),
            @display {label: "CC"}
            string[]? cc = (),
            @display {label: "BCC"}
            string[]? bcc = ()
    ) returns Draft|error {
        MessageRequest message = {
            to: (to is string) ? [to] : to,
            subject
        };
        message = addOptionalFields(message, textBody, htmlBody, cc, bcc);
        return self.baseClient->/users/me/drafts.post({message});
    }

    # Retrieves a file attachment from an email message.
    #
    # Attachment IDs are found in the Message returned by read — each MessagePart
    # with a non-empty attachmentId field represents a downloadable attachment.
    #
    # + messageId - The ID of the message that contains the attachment
    # + attachmentId - The ID of the attachment to retrieve
    # + return - The Attachment containing the base64url-encoded file data, or an error
    @operation
    @display {label: "Get Attachment"}
    isolated remote function getAttachment(
            @display {label: "Message ID"}
            string messageId,
            @display {label: "Attachment ID"}
            string attachmentId
    ) returns Attachment|error {
        return self.baseClient->/users/me/messages/[messageId]/attachments/[attachmentId]();
    }
}
${tbq}
`;
}

function getInitialGenerationUserPrompt(ConnectorContext ctx) returns string {
    string openApiSection = ctx.openApiSpecContent.length() > 0
        ? string `<OPENAPI_SPEC>
${ctx.openApiSpecContent}
</OPENAPI_SPEC>`
        : "Note: No OpenAPI specification was found. Infer operation semantics from client.bal alone.";

    return string `Connector org: ${ctx.connectorOrg}
Connector name: ${ctx.connectorName}
Total resource/remote methods in Client: ${ctx.resourceMethodCount}

---

<CLIENT_BAL>
${ctx.clientBalContent}
</CLIENT_BAL>

<TYPES_BAL>
${ctx.typesBalContent}
</TYPES_BAL>

${openApiSection}

---

Follow these steps exactly:

## Step 1 — Identify the connector domain and authentication scheme

From the provided files:
- What is the connector's primary domain? (Email, CRM, Storage, Messaging, Calendar, Database, Other)
- What is the connector's primary entity type?
- What authentication scheme does the Client use?
- What fields does the auth record in ConnectionConfig require?

## Step 2 — Score and select operations

For each endpoint (resource/remote function) in the client:
1. Assign a score from 0–30: Popularity + Simplification Potential + Domain Essentiality.
2. Produce a scoring table:

| Endpoint | Popularity | Simplification | Essentiality | Total | Include? |
|----------|-----------|----------------|--------------|-------|----------|

3. Select qualifying operations (score ≥ 15) up to the count target for ${ctx.resourceMethodCount} methods.
   Ensure CRUD coverage for the primary entity.

4. For each selected operation, plan:
   - Operation name (following naming rules)
   - Simplified parameter list (flattened from the raw endpoint)
   - Return type
   - Delegation strategy (which Client function(s) to call; composite calls where appropriate)

## Step 3 — Generate connector.bal

Produce the complete ${bq}connector.bal${bq} following the pattern from the system prompt.

The file MUST:
- Start with the WSO2 license header
- Define AuthConfig (auth-only fields, @display on type and all fields, # doc comments)
- Include any needed private helper functions
- Define ${bq}public isolated client class Connector${bq} with ${bq}init${bq}, ${bq}getClient${bq}, and all selected operations
- Have ${bq}@operation${bq} + ${bq}@display${bq} + ${bq}isolated${bq} + full # doc comment on every remote method
- Have ${bq}@display {label: "..."}${bq} on every parameter

## Output format

Your response MUST use EXACTLY these delimiters — no other text outside the sections:

---SELECTION_REPORT---
### Selection Summary
- Connector domain: ...
- Primary entity: ...
- Total Client resource methods: ${ctx.resourceMethodCount}
- Operations selected: N

### Scoring Table
<table>

### Design Decisions
- AuthConfig fields: ...
- Composite operations: ...
- Naming deviations: ...

---CONNECTOR_BAL---
<complete connector.bal content, no markdown fences>
`;
}
