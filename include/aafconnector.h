/*
 * Copyright 2026 NXP
 *
 * NXP Proprietary. This software is owned or controlled by NXP and may only be
 * used strictly in accordance with the applicable license terms.  By expressly
 * accepting such terms or by downloading, installing, activating and/or
 * otherwise using the software, you are agreeing that you have read, and that
 * you agree to comply with and are bound by, such license terms.  If you do
 * not agree to be bound by the applicable license terms, then you may not
 * retain, install, activate or otherwise use the software.
 *
 * @file aafconnector.h
 * @brief eIQ AAF Connector for remote inference
 *
 */

#ifndef AAFCONNECTOR_H
#define AAFCONNECTOR_H

#include <QObject>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QJsonObject>
#include <QJsonDocument>
#include <QTimer>
#include <QLoggingCategory>

Q_DECLARE_LOGGING_CATEGORY(lcConnector)

namespace AAFConfig {
    // Models paths
    inline const QString CONFIG_PATH = QStringLiteral("/usr/share/vlm-edge-studio/server_config.json");
    inline const QString MODEL_PATH = QStringLiteral("/usr/share/llm");

    // Server settings
    inline const QString DEFAULT_SERVER_URL = QStringLiteral("http://localhost:8000");
    inline const int DEFAULT_TIMEOUT_MS = 240000;

    // API endpoints
    inline const QString ENDPOINT_CHAT = QStringLiteral("/v1/chat/completions");
    inline const QString ENDPOINT_MODELS = QStringLiteral("/v1/models");
    inline const QString ENDPOINT_METRICS = QStringLiteral("/metrics/");
}

class AAFConnector : public QObject
{
    Q_OBJECT

public:
    explicit AAFConnector(QObject *parent = nullptr);
    ~AAFConnector();

    // Model information structure
    struct ModelInfo {
        QString name;           // "nxp/Qwen2_5-VL-7B-Instruct-Ara240"
        QString description;    // "Qwen2.5-VL 7B Istruct instance with vision..."
        QString type;           // "qwen_vl", "text"
        QString toolCalling;    // "native", "non-native", "no"
        int maxPromptSize;      // 2047
        bool enabled;           // true, false
        bool supportsVideo;     // Derived from type
        bool supportsImage;     // Derived from type

        ModelInfo()
            : maxPromptSize(2048)
            , enabled(false)
            , supportsVideo(false)
            , supportsImage(false)
        {}
    };

    // Model status structure
    struct ModelStatus {
        QString name;
        QString id;
        QString description;
        bool ready;

        ModelStatus()
            : name("")
            , id("")
            , description("")
            , ready(false)
        {}
    };

    // Request types
    enum RequestType {
        TEXT_COMPLETION,
        CHAT_COMPLETION,
        VISION_COMPLETION
    };
    Q_ENUM(RequestType)

    // Simple API
    void setServerUrl(const QString &url);
    void setTimeout(int timeoutMs = 30000);

    // Text-based requests
    void sendTextPrompt(const QString &prompt);

    // Vision-based requests
    void sendVisionPrompt(const QString &prompt, const QString &mediaPath, const QString &mediaType);

    // Metrics request
    void requestMetrics(const QString &modelName = QString());

    // Model management
    void loadModelsFromConfig(const QString &configPath);
    void setModelById(const QString &modelId);

    void cancelRequest();
    bool isProcessing() const { return m_isProcessing; }

    Q_INVOKABLE void connectToServer();

    // Model management
    void loadModel(const ModelInfo &modelInfo);
    void removeModel(const QString &modelName);
    void checkModelStatus(const QString &modelName);

Q_SIGNALS:
    void responseReceived(const QString &response);
    void tokenReceived(const QString &token);
    void errorOccurred(const QString &error);
    void requestStarted();
    void requestFinished();

    // Metrics signal - returns formatted string
    void metricsReceived(const QString &metricsText);

    // Status signals
    void connectionEstablished();
    void connectionStatusChanged();
    void connectionLost();

    // Model list signals
    void modelsListReceived(const QList<ModelInfo> &models);
    void modelsListError(const QString &error);

    // Model management signals
    void modelLoadStarted(const QString &modelName);
    void modelLoadCompleted(const QString &modelName);
    void modelRemoved(const QString &modelName);
    void modelOperationError(const QString &error);

    // Model status signals
    void modelStatusReceived(const ModelStatus &status);
    void modelReady(const QString &modelName);
    void modelStillLoading(const QString &modelName, int progress);

private Q_SLOTS:
    void handleNetworkReply();
    void handleNetworkError(QNetworkReply::NetworkError error);
    void onRequestTimeout();
    void handleStreamingData();
    void handleMetricsReply();
    void handleModelStatusReply();

private:
    // Connection management
    void disconnectFromServer();

    // Core components
    QNetworkAccessManager *m_networkManager;
    QNetworkReply *m_currentReply;
    QTimer *m_timeoutTimer;

    // Configuration
    QString m_serverUrl;
    QString m_currentModelId;    // Dynamic model ID from config
    QString m_apiKey;
    int m_timeout;
    bool m_isConnected;
    bool m_isProcessing;

    // Request tracking
    RequestType m_currentRequestType;
    QString m_currentRequestId;

    QTimer *m_modelStatusTimer;
    QString m_loadingModelName;

    // Helper methods
    QNetworkRequest createRequest() const;
    QNetworkRequest createMetricsRequest(const QString &modelName) const;
    QString formatMetrics(const QJsonObject &metrics) const;
    QString formatModelName(const QString &modelId) const;
    QJsonObject createTextPayload(const QString &prompt) const;
    QJsonObject createVideoPayload(const QString &prompt, const QString &videoPath) const;
    QJsonObject createImagePayload(const QString &prompt, const QString &imagePath) const;
    void sendRequest(const QJsonObject &payload);
    void processResponse(const QJsonDocument &doc);
    void setProcessingState(bool processing);
    void setConnectionState(bool connected);
    bool validateModelInstallation(const QString &modelName);

    // Config parsing
    bool parseServerConfig(const QString &configPath, QList<ModelInfo> &models);

    void handleModelLoadReply();
    void handleModelRemoveReply();

    QNetworkRequest createModelStatusRequest(const QString &modelName) const;
    void startModelStatusPolling(const QString &modelName);
    void stopModelStatusPolling();
};

#endif