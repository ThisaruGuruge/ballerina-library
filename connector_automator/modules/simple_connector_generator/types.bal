public type ConnectorContext record {|
    string connectorPath;
    string ballerinaPath;
    string clientBalContent;
    string typesBalContent;
    string openApiSpecContent;
    string connectorBalContent;
    boolean isRepairMode;
    int resourceMethodCount;
    string connectorOrg;
    string connectorName;
|};

public type GenerationResult record {|
    boolean success;
    string connectorBalPath;
    string selectionReport;
    boolean wasRepaired;
|};

