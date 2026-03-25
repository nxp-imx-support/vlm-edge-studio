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
 */

#include "aafconnector.h"
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QDirIterator>
#include <QJsonArray>
#include <QJsonParseError>
#include <QLoggingCategory>
#include <QNetworkRequest>
#include <QUrlQuery>

Q_LOGGING_CATEGORY(lcConnector, "aaf.connector")

AAFConnector::AAFConnector(QObject *parent)
    : QObject(parent)
    , m_networkManager(new QNetworkAccessManager(this))
    , m_currentReply(nullptr)
    , m_timeoutTimer(new QTimer(this))
    , m_serverUrl(AAFConfig::DEFAULT_SERVER_URL)
    , m_currentModelId("")
    , m_apiKey("")
    , m_timeout(AAFConfig::DEFAULT_TIMEOUT_MS)
    , m_isConnected(false)
    , m_isProcessing(false)
    , m_modelStatusTimer(new QTimer(this))
    , m_loadingModelName("")
{
    m_timeoutTimer->setSingleShot(true);
    connect(m_timeoutTimer, &QTimer::timeout, this, &AAFConnector::onRequestTimeout);

    // Setup model status polling timer
    m_modelStatusTimer->setInterval(2000);
    connect(m_modelStatusTimer, &QTimer::timeout, this, [this]() {
        if (!m_loadingModelName.isEmpty()) {
            checkModelStatus(m_loadingModelName);
        }
    });
}

AAFConnector::~AAFConnector()
{
    stopModelStatusPolling();

    if (m_currentReply) {
        m_currentReply->abort();
        m_currentReply->deleteLater();
    }
}

void AAFConnector::setServerUrl(const QString &url)
{
    m_serverUrl = url;
}

void AAFConnector::setTimeout(int timeoutMs)
{
    m_timeout = timeoutMs;
}

// Text-only prompt
void AAFConnector::sendTextPrompt(const QString &prompt)
{
    if (m_isProcessing) {
        Q_EMIT errorOccurred("Request already in progress");
        return;
    }
    
    if (prompt.isEmpty()) {
        Q_EMIT errorOccurred("Empty prompt provided");
        return;
    }

    QJsonObject payload = createTextPayload(prompt);
    sendRequest(payload);

    qCDebug(lcConnector) << "Text prompt sent:" << prompt.left(50) + "...";
}

// Vision prompt with media file path
void AAFConnector::sendVisionPrompt(const QString &prompt, const QString &mediaPath, const QString &mediaType)
{
    if (m_isProcessing) {
        Q_EMIT errorOccurred("Request already in progress");
        return;
    }

    if (prompt.isEmpty() || mediaPath.isEmpty()) {
        Q_EMIT errorOccurred("Empty prompt or media path provided");
        return;
    }

    if (!QFileInfo::exists(mediaPath)) {
        Q_EMIT errorOccurred("Media file does not exist: " + mediaPath);
        return;
    }

    qCDebug(lcConnector) << "Vision prompt:" << prompt << "sent with media:" << mediaPath;
    
    // Create video/image payload and send request
    QJsonObject payload;
    if(mediaType == "video") {
        payload = createVideoPayload(prompt, mediaPath);
    } else if (mediaType == "image") {
        payload = createImagePayload(prompt, mediaPath);
    }

    sendRequest(payload);
}

void AAFConnector::cancelRequest()
{
    if (m_currentReply) {
        m_currentReply->abort();
        setProcessingState(false);
        m_timeoutTimer->stop();
        qCDebug(lcConnector) << "Request cancelled";
    }
}

void AAFConnector::connectToServer()
{
    qCDebug(lcConnector) << "Attempting to connect to server:" << m_serverUrl;
    this->loadModelsFromConfig(AAFConfig::CONFIG_PATH);
}

void AAFConnector::disconnectFromServer()
{
    if (m_currentReply) {
        m_currentReply->abort();
    }
    setConnectionState(false);
    qCDebug(lcConnector) << "Disconnected from server";
}

void AAFConnector::loadModelsFromConfig(const QString &configPath)
{
    qCDebug(lcConnector) << "Loading models from config:" << configPath;
    QList<ModelInfo> models;

    if (parseServerConfig(configPath, models)) {
        QList<ModelInfo> enabledModels;
        for (const ModelInfo &model : models) {
            if (validateModelInstallation(model.name)) {
                enabledModels.append(model);
            }
        }
        if (enabledModels.isEmpty()) {
            qCWarning(lcConnector) << "No enabled models found in config";
            Q_EMIT modelsListError("No enabled models found in configuration");
        } else {
            qCDebug(lcConnector) << "Found " << enabledModels.size() << "model(s) installed";
            Q_EMIT modelsListReceived(enabledModels);
        }
    } else {
        qCWarning(lcConnector) << "Failed to parse server config";
        Q_EMIT modelsListError("Failed to parse server configuration file");
    }
}

bool AAFConnector::parseServerConfig(const QString &configPath, QList<ModelInfo> &models)
{
    QFile configFile(configPath);

    if (!configFile.open(QIODevice::ReadOnly | QIODevice::Text)) {
        qCWarning(lcConnector) << "Failed to open config file:" << configPath;
        qCWarning(lcConnector) << "Error:" << configFile.errorString();
        return false;
    }

    QByteArray jsonData = configFile.readAll();
    configFile.close();

    QJsonParseError parseError;
    QJsonDocument doc = QJsonDocument::fromJson(jsonData, &parseError);

    if (parseError.error != QJsonParseError::NoError) {
        qCWarning(lcConnector) << "JSON parse error:" << parseError.errorString();
        qCWarning(lcConnector) << "At offset:" << parseError.offset;
        return false;
    }

    if (!doc.isObject()) {
        qCWarning(lcConnector) << "Config root is not a JSON object";
        return false;
    }

    QJsonObject rootObj = doc.object();

    if (!rootObj.contains("available_models") || !rootObj["available_models"].isArray()) {
        qCWarning(lcConnector) << "Config missing 'available_models' array";
        return false;
    }

    QJsonArray modelsArray = rootObj["available_models"].toArray();

    for (const QJsonValue &value : modelsArray) {
        if (!value.isObject()) {
            continue;
        }

        QJsonObject modelObj = value.toObject();

        ModelInfo info;
        info.name = modelObj["name"].toString();
        info.description = modelObj["description"].toString();
        info.type = modelObj["type"].toString();
        info.toolCalling = modelObj["tool_calling"].toString();
        info.maxPromptSize = modelObj.value("max_prompt_size").toInt(2048);
        info.enabled = modelObj["enabled"].toBool(false);

        // Determine vision capabilities based on type
        if (info.type == "qwen_vl_video") {
            info.supportsVideo = true;
            info.supportsImage = false;
        } else if (info.type == "qwen_vl_image") {
            info.supportsVideo = false;
            info.supportsImage = true;
        } else if (info.type == "text") {
            info.supportsVideo = false;
            info.supportsImage = false;
        } else {
            // Unknown type, assume basic capabilities
            info.supportsVideo = false;
            info.supportsImage = false;
        }

        // Support multimodal only if enabled and has capabilities
        if (info.type == "qwen_vl_video" || info.type == "qwen_vl_image") {
			qCDebug(lcConnector) << "Model: " << info.name << " Type:" << info.type;
            models.append(info);
        }
    }

    return true;
}

QString AAFConnector::formatModelName(const QString &modelId) const
{
    // Convert model name to friendly display name
    QString name = modelId;

    // Replace hyphens and underscores with spaces
    name.replace("-", " ");
    name.replace("_", ".");

    // Capitalize first letter of each word
    QStringList words = name.split(" ", Qt::SkipEmptyParts);
    for (QString &word : words) {
        if (!word.isEmpty()) {
            // Keep version numbers and sizes as-is (e.g., "7b", "3b", "2.5")
            if (word[0].isDigit()) {
                word = word.toUpper();
            } else {
                word[0] = word[0].toUpper();
            }
        }
    }

    return words.join(" ");
}

void AAFConnector::setModelById(const QString &modelId)
{
    if (m_currentModelId == modelId) {
        qCDebug(lcConnector) << "Model already set to:" << modelId;
        return;
    }
    qCDebug(lcConnector) << "Setting model to:" << modelId;
}

void AAFConnector::handleNetworkReply()
{
    QNetworkReply *reply = qobject_cast<QNetworkReply*>(sender());
    if (!reply) {
        qCWarning(lcConnector) << "[METRICS DEBUG] handleNetworkReply: reply is null!";
        return;
    }

    m_timeoutTimer->stop();

    if (reply->error() == QNetworkReply::NoError) {
        QByteArray data = reply->readAll();

        // Handle streaming response (Server-Sent Events format)
        QString dataStr = QString::fromUtf8(data);
        QStringList lines = dataStr.split('\n');

        QString fullResponse;
        bool streamCompleted = false;
        int lineNumber = 0;

        for (const QString &line : lines) {
            lineNumber++;

            if (line.startsWith("data: ")) {
                QString jsonStr = line.mid(6).trimmed();
                if (jsonStr == "[DONE]") {
                    qCDebug(lcConnector) << "Stream completed - [DONE] received at line" << lineNumber;
                    streamCompleted = true;
                    continue;
                }

                QJsonParseError parseError;
                QJsonDocument doc = QJsonDocument::fromJson(jsonStr.toUtf8(), &parseError);

                if (parseError.error == QJsonParseError::NoError) {
                    QJsonObject obj = doc.object();

                    if (obj.contains("choices")) {
                        QJsonArray choices = obj["choices"].toArray();
                        if (!choices.isEmpty()) {
                            QJsonObject firstChoice = choices[0].toObject();
                            QJsonObject delta = firstChoice["delta"].toObject();

                            if (delta.contains("content")) {
                                QString token = delta["content"].toString();
                                fullResponse += token;
                                Q_EMIT tokenReceived(token);
                            }
                        }
                    }
                } else {
                    qCWarning(lcConnector) << "Failed to parse JSON:" << parseError.errorString();
                    qCWarning(lcConnector) << "JSON string was:" << jsonStr;
                }
            } else if (!line.trimmed().isEmpty()) {
                qCDebug(lcConnector) << "Non-data line:" << line;
            }
        }

        // Final state
        qCDebug(lcConnector) << "Stream processing complete";
        if (!fullResponse.isEmpty()) {
            Q_EMIT responseReceived(fullResponse);
            qCDebug(lcConnector) << "Complete response:" << fullResponse;
        }

        // Always request metrics when reply finishes successfully
        if (streamCompleted || reply->isFinished()) {
            QTimer::singleShot(500, this, [this]() {
                requestMetrics(m_currentModelId);
            });
        }
    } else {
        qCWarning(lcConnector) << "Network error:" << reply->errorString();
    }

    setProcessingState(false);
    reply->deleteLater();
    if (reply == m_currentReply) {
        m_currentReply = nullptr;
    }

}

void AAFConnector::handleStreamingData()
{
    QNetworkReply *reply = qobject_cast<QNetworkReply*>(sender());
    if (!reply) {
        return;
    }

    QByteArray data = reply->readAll();
    QString dataStr = QString::fromUtf8(data);
    QStringList lines = dataStr.split('\n');

    for (const QString &line : lines) {
        if (line.startsWith("data: ")) {
            QString jsonStr = line.mid(6).trimmed();

            if (jsonStr == "[DONE]") {
                qCDebug(lcConnector) << "Stream [DONE] marker received in handleStreamingData";
                continue;
            }

            QJsonParseError parseError;
            QJsonDocument doc = QJsonDocument::fromJson(jsonStr.toUtf8(), &parseError);

            if (parseError.error == QJsonParseError::NoError) {
                QJsonObject obj = doc.object();

                if (obj.contains("choices")) {
                    QJsonArray choices = obj["choices"].toArray();
                    if (!choices.isEmpty()) {
                        QJsonObject firstChoice = choices[0].toObject();
                        QJsonObject delta = firstChoice["delta"].toObject();

                        if (delta.contains("content")) {
                            QString token = delta["content"].toString();
                            Q_EMIT tokenReceived(token);
                        }
                    }
                }
            }
        }
    }
}

void AAFConnector::requestMetrics(const QString &modelName)
{
    QString model = modelName.isEmpty() ? m_currentModelId : modelName;
    qCDebug(lcConnector) << "Requesting metrics for model:" << model;

    QNetworkRequest request = createMetricsRequest(model);
    QNetworkReply *reply = m_networkManager->get(request);

    connect(reply, &QNetworkReply::finished, this, &AAFConnector::handleMetricsReply);
    connect(reply, QOverload<QNetworkReply::NetworkError>::of(&QNetworkReply::errorOccurred),
            this, &AAFConnector::handleNetworkError);
}

QNetworkRequest AAFConnector::createMetricsRequest(const QString &modelName) const
{
    QUrl url(m_serverUrl + "/metrics/");
    QUrlQuery query;
    query.addQueryItem("model_name", modelName);
    url.setQuery(query);

    QNetworkRequest request(url);
    request.setHeader(QNetworkRequest::UserAgentHeader, "AAFConnector/1.0");
    request.setRawHeader("Accept", "application/json");
    qCDebug(lcConnector) << "Created metrics request URL:" << url.toString();

    return request;
}

void AAFConnector::handleMetricsReply()
{
    QNetworkReply *reply = qobject_cast<QNetworkReply*>(sender());
    if (!reply) {
        qCWarning(lcConnector) << "handleMetricsReply: reply is null";
        return;
    }

    if (reply->error() == QNetworkReply::NoError) {
        QByteArray data = reply->readAll();
        QJsonParseError parseError;
        QJsonDocument doc = QJsonDocument::fromJson(data, &parseError);

        if (parseError.error == QJsonParseError::NoError) {
            QJsonObject rootObject = doc.object();

            QJsonObject metrics;
            if (rootObject.contains(m_currentModelId)) {
                // Direct model key found
                metrics = rootObject[m_currentModelId].toObject();
                qCDebug(lcConnector) << "Found metrics for model:" << m_currentModelId;
            } else if (!rootObject.isEmpty()) {
                // Take first model's metrics (fallback)
                QString firstKey = rootObject.keys().first();
                metrics = rootObject[firstKey].toObject();
                qCDebug(lcConnector) << "Using metrics from model:" << firstKey;
            } else {
                qCWarning(lcConnector) << "Empty metrics object received";
                Q_EMIT errorOccurred("No metrics data available");
                reply->deleteLater();
                return;
            }

            QString metricsText = formatMetrics(metrics);
            qCDebug(lcConnector) << "Formatted metrics:" << metricsText;

            Q_EMIT metricsReceived(metricsText);
        } else {
            qCWarning(lcConnector) << "Failed to parse metrics JSON:" << parseError.errorString();
            qCWarning(lcConnector) << "Raw data was:" << data;
            Q_EMIT errorOccurred("Failed to parse metrics: " + parseError.errorString());
        }
    } else {
        qCWarning(lcConnector) << "Metrics request failed:" << reply->errorString();
        qCWarning(lcConnector) << "HTTP status code:" << reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        Q_EMIT errorOccurred("Metrics request failed: " + reply->errorString());
    }

    reply->deleteLater();
}

QString AAFConnector::formatMetrics(const QJsonObject &metrics) const
{
    QStringList compact;

    // Compact display
    if (metrics.contains("llm_average_token_per_second")) {
        double tps = metrics["llm_average_token_per_second"].toDouble();
        compact << QString("%1 tok/s").arg(tps, 0, 'f', 1);
    }
    if (metrics.contains("llm_first_infer_duration")) {
        double ttft = metrics["llm_first_infer_duration"].toDouble();
        compact << QString("TTFT: %1s").arg(ttft, 0, 'f', 2);
    }
    if (metrics.contains("generated_token_num")) {
        compact << QString("%1 tokens").arg(metrics["generated_token_num"].toInt());
    }

    return compact.join(" • ");
}

void AAFConnector::handleNetworkError(QNetworkReply::NetworkError error)
{
    QNetworkReply *reply = qobject_cast<QNetworkReply*>(sender());
    if (!reply) return;

    m_timeoutTimer->stop();
    setProcessingState(false);
    setConnectionState(false);

    QString errorString;
    if (error == QNetworkReply::TimeoutError) {
        errorString = "Request timeout occurred";
    } else if (error == QNetworkReply::ConnectionRefusedError) {
        errorString = "Connection refused by server";
    } else if (error == QNetworkReply::HostNotFoundError) {
        errorString = "Host not found";
    }
    Q_EMIT errorOccurred(errorString);
}

void AAFConnector::onRequestTimeout()
{
    if (m_currentReply) {
        m_currentReply->abort();
    }
    setProcessingState(false);
    Q_EMIT errorOccurred("Request timed out after " + QString::number(m_timeout / 1000) + " seconds");
}

// Private helper methods
QNetworkRequest AAFConnector::createRequest() const
{
    QUrl url(m_serverUrl + "/v1/chat/completions");
    QNetworkRequest request(url);

    request.setHeader(QNetworkRequest::ContentTypeHeader, "application/json");
    request.setHeader(QNetworkRequest::UserAgentHeader, "AAFConnector/1.0");
    request.setRawHeader("Accept", "application/json");

    return request;
}

QJsonObject AAFConnector::createTextPayload(const QString &prompt) const
{
    QJsonObject payload;
    payload["model"] = m_currentModelId;
    payload["stream"] = true;

    QJsonArray messages;
    QJsonObject userMsg;
    userMsg["role"] = "user";
    userMsg["content"] = prompt;
    messages.append(userMsg);

    payload["messages"] = messages;
    qCDebug(lcConnector) << "Created text payload with model:" << m_currentModelId;

    return payload;
}

QJsonObject AAFConnector::createVideoPayload(const QString &prompt, const QString &videoPath) const
{
    QJsonObject payload;
    payload["model"] = m_currentModelId;
    payload["stream"] = true;

    QJsonArray messages;
    QJsonObject userMsg;
    userMsg["role"] = "user";

    // Create content array with text and video_url
    QJsonArray content;

    // Text part
    QJsonObject textPart;
    textPart["type"] = "text";
    textPart["text"] = prompt;
    content.append(textPart);

    // Video part
    QJsonObject videoPart;
    videoPart["type"] = "video_url";

    QJsonObject videoUrl;
    videoUrl["url"] = videoPath;
    videoPart["video_url"] = videoUrl;

    content.append(videoPart);

    userMsg["content"] = content;
    messages.append(userMsg);

    payload["messages"] = messages;

    qCDebug(lcConnector) << "Created video payload with model:" << m_currentModelId;

    return payload;
}

QJsonObject AAFConnector::createImagePayload(const QString &prompt, const QString &imagePath) const
{
    QJsonObject payload;
    payload["model"] = m_currentModelId;
    payload["stream"] = true;

    QJsonArray messages;
    QJsonObject userMsg;
    userMsg["role"] = "user";

    // Create content array with text and image_url
    QJsonArray content;

    // Text part
    QJsonObject textPart;
    textPart["type"] = "text";
    textPart["text"] = prompt;
    content.append(textPart);

    // Image part
    QJsonObject imagePart;
    imagePart["type"] = "image_url";

    QJsonObject imageUrl;
    imageUrl["url"] = imagePath;
    imagePart["image_url"] = imageUrl;

    content.append(imagePart);

    userMsg["content"] = content;
    messages.append(userMsg);

    payload["messages"] = messages;

    qCDebug(lcConnector) << "Created image payload with model:" << m_currentModelId;

    return payload;
}

void AAFConnector::sendRequest(const QJsonObject &payload)
{
    if (m_isProcessing) {
        Q_EMIT errorOccurred("Request already in progress");
        return;
    }

    QNetworkRequest request = createRequest();
    QJsonDocument doc(payload);
    QByteArray jsonData = doc.toJson(QJsonDocument::Compact);

    m_currentReply = m_networkManager->post(request, jsonData);

    qCDebug(lcConnector) << "Connected signals:";
    qCDebug(lcConnector) << "   readyRead -> handleStreamingData";
    qCDebug(lcConnector) << "   finished -> handleNetworkReply";

    connect(m_currentReply, &QNetworkReply::readyRead, this, &AAFConnector::handleStreamingData);
    connect(m_currentReply, &QNetworkReply::finished, this, &AAFConnector::handleNetworkReply);
    connect(m_currentReply, QOverload<QNetworkReply::NetworkError>::of(&QNetworkReply::errorOccurred),
            this, &AAFConnector::handleNetworkError);

    setProcessingState(true);
    m_timeoutTimer->start(m_timeout);
}

void AAFConnector::processResponse(const QJsonDocument &doc)
{
    QJsonObject response = doc.object();
    if (doc.isNull() || response.isEmpty()) {
        Q_EMIT errorOccurred("Empty response from server");
        return;
    }

    qCDebug(lcConnector) << "Processing response:" << doc.toJson(QJsonDocument::Compact);

    // Extract the response text from the API response
    if (response.contains("choices")) {
        QJsonArray choices = response["choices"].toArray();
        if (!choices.isEmpty()) {
            QJsonObject firstChoice = choices[0].toObject();
            QJsonObject message = firstChoice["message"].toObject();
            QString content = message["content"].toString();

            qCDebug(lcConnector) << "Extracted response content:" << content;
            Q_EMIT responseReceived(content);
        }
    } else {
        qCWarning(lcConnector) << "Unexpected response format:" << doc.toJson();
        Q_EMIT errorOccurred("Unexpected response format from server");
    }
}

void AAFConnector::setProcessingState(bool processing)
{
    if (m_isProcessing != processing) {
        m_isProcessing = processing;
        
        if (processing) {
            Q_EMIT requestStarted();
        } else {
            Q_EMIT requestFinished();
        }
    }
}

void AAFConnector::setConnectionState(bool connected)
{
    if (m_isConnected != connected) {
        m_isConnected = connected;
        Q_EMIT connectionStatusChanged();
        if (connected) {
            Q_EMIT connectionEstablished();
        } else {
            Q_EMIT connectionLost();
        }
    }
}

bool AAFConnector::validateModelInstallation(const QString &modelName)
{
    if (modelName.isEmpty()) {
        Q_EMIT modelOperationError("Model name cannot be empty");
        return false;
    }
    // Construct the model directory path
    QString modelPath = QString("%1/%2").arg(AAFConfig::MODEL_PATH, modelName);
    QDir modelDir(modelPath);

    if (!modelDir.exists()) {
        return false;
    }

    // Recursively search for model.dvm file
    QDirIterator it(modelPath, QStringList() << "model.dvm",
                    QDir::Files, QDirIterator::Subdirectories);

    if (it.hasNext()) {
        QString dvmPath = it.next();
        qCDebug(lcConnector) << "Found model.dvm at:" << dvmPath;
        return true;
    } else {
        qCWarning(lcConnector) << "model.dvm not found in:" << modelPath;
        Q_EMIT modelOperationError("model.dvm not found for model: " + modelName);
        return false;
    }
}

void AAFConnector::loadModel(const ModelInfo &modelInfo)
{
    if (modelInfo.name.isEmpty()) {
        Q_EMIT modelOperationError("Empty model name provided");
        return;
    }

    qCDebug(lcConnector) << "Loading model:" << modelInfo.name
                         << "type:" << modelInfo.type;

    QUrl url(m_serverUrl + "/v1/models");
    QNetworkRequest request(url);

    request.setHeader(QNetworkRequest::ContentTypeHeader, "application/json");
    request.setHeader(QNetworkRequest::UserAgentHeader, "AAFConnector/1.0");
    request.setRawHeader("Accept", "application/json");

    // Create payload
    QJsonObject payload;
    payload["name"] = modelInfo.name;
    payload["type"] = modelInfo.type;
    payload["tool_calling"] = modelInfo.toolCalling;

    QJsonDocument doc(payload);
    QByteArray jsonData = doc.toJson(QJsonDocument::Compact);

    qCDebug(lcConnector) << "Sending model load request to:" << url.toString();
    qCDebug(lcConnector) << "Payload:" << jsonData;

    QNetworkReply *reply = m_networkManager->post(request, jsonData);

    connect(reply, &QNetworkReply::finished, this, &AAFConnector::handleModelLoadReply);
    connect(reply, QOverload<QNetworkReply::NetworkError>::of(&QNetworkReply::errorOccurred),
            this, &AAFConnector::handleNetworkError);

    Q_EMIT modelLoadStarted(modelInfo.name);

     // Start polling for model status
    startModelStatusPolling(modelInfo.name);
}

void AAFConnector::removeModel(const QString &modelName)
{
    if (modelName.isEmpty()) {
        Q_EMIT modelOperationError("Empty model name provided");
        return;
    }

    qCDebug(lcConnector) << "Removing model:" << modelName;
    QUrl url(m_serverUrl + "/v1/models/" + modelName);
    QNetworkRequest request(url);

    request.setHeader(QNetworkRequest::UserAgentHeader, "AAFConnector/1.0");
    request.setRawHeader("Accept", "application/json");

    qCDebug(lcConnector) << "Sending model remove request to:" << url.toString();
    QNetworkReply *reply = m_networkManager->deleteResource(request);

    // Store model name in reply property for later use
    reply->setProperty("modelName", modelName);

    connect(reply, &QNetworkReply::finished, this, &AAFConnector::handleModelRemoveReply);
    connect(reply, QOverload<QNetworkReply::NetworkError>::of(&QNetworkReply::errorOccurred),
            this, &AAFConnector::handleNetworkError);
}

void AAFConnector::handleModelLoadReply()
{
    QNetworkReply *reply = qobject_cast<QNetworkReply*>(sender());
    if (!reply) {
        qCWarning(lcConnector) << "handleModelLoadReply: reply is null";
        return;
    }

    qCDebug(lcConnector) << "HTTP status code:" << reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();

    if (reply->error() == QNetworkReply::NoError) {
        QByteArray data = reply->readAll();

        QJsonParseError parseError;
        QJsonDocument doc = QJsonDocument::fromJson(data, &parseError);

        if (parseError.error == QJsonParseError::NoError) {
            QJsonObject response = doc.object();
            QString detail = response["detail"].toString();

            int statusCode = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
            if (statusCode == 201) {
                // Model already loaded
                qCDebug(lcConnector) << "Model already loaded";
                stopModelStatusPolling();
                Q_EMIT modelLoadCompleted(m_currentModelId);
            } else if (statusCode == 202) {
                // Model loading initiated
                qCDebug(lcConnector) << "Model loading in progress";
            }
        } else {
            qCWarning(lcConnector) << "Failed to parse model load response:" << parseError.errorString();
            stopModelStatusPolling();
            Q_EMIT modelOperationError("Failed to parse response: " + parseError.errorString());
        }
    } else {
        qCWarning(lcConnector) << "Model load request failed:" << reply->errorString();
        stopModelStatusPolling();
        Q_EMIT modelOperationError("Model load failed: " + reply->errorString());
    }

    reply->deleteLater();
}

void AAFConnector::handleModelRemoveReply()
{
    QNetworkReply *reply = qobject_cast<QNetworkReply*>(sender());
    if (!reply) {
        qCWarning(lcConnector) << "handleModelRemoveReply: reply is null";
        return;
    }

    QString modelName = reply->property("modelName").toString();

    qCDebug(lcConnector) << "Model remove reply received for:" << modelName;
    qCDebug(lcConnector) << "Status:" << reply->error();
    qCDebug(lcConnector) << "HTTP status code:" << reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();

    if (reply->error() == QNetworkReply::NoError) {
        QByteArray data = reply->readAll();
        qCDebug(lcConnector) << "Model remove response:" << data;

        int statusCode = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();

        if (statusCode == 200) {
            qCDebug(lcConnector) << "Model successfully removed:" << modelName;
            m_currentModelId.clear();
            Q_EMIT modelRemoved(modelName);
        } else {
            qCWarning(lcConnector) << "Unexpected status code:" << statusCode;
            Q_EMIT modelOperationError("Unexpected response code: " + QString::number(statusCode));
        }
    } else if (reply->error() == QNetworkReply::ContentNotFoundError) {
        qCWarning(lcConnector) << "Model not found:" << modelName;
        Q_EMIT modelOperationError("Model not found: " + modelName);
    } else {
        qCWarning(lcConnector) << "Model remove request failed:" << reply->errorString();
        Q_EMIT modelOperationError("Model remove failed: " + reply->errorString());
    }

    reply->deleteLater();
}

QNetworkRequest AAFConnector::createModelStatusRequest(const QString &modelName) const
{
    QUrl url(m_serverUrl + "/v1/models/" + modelName);
    QNetworkRequest request(url);

    request.setHeader(QNetworkRequest::UserAgentHeader, "AAFConnector/1.0");
    request.setRawHeader("Accept", "application/json");

    return request;
}

void AAFConnector::startModelStatusPolling(const QString &modelName)
{
    qCDebug(lcConnector) << "Starting model status polling for:" << modelName;
    m_loadingModelName = modelName;
    m_modelStatusTimer->start();

    // Immediately check status
    checkModelStatus(modelName);
}

void AAFConnector::stopModelStatusPolling()
{
    qCDebug(lcConnector) << "Stopping model status polling";
    m_modelStatusTimer->stop();
    m_loadingModelName.clear();
}

void AAFConnector::checkModelStatus(const QString &modelName)
{
    if (modelName.isEmpty()) {
        qCWarning(lcConnector) << "Cannot check status: empty model name";
        return;
    }

    QNetworkRequest request = createModelStatusRequest(modelName);
    QNetworkReply *reply = m_networkManager->get(request);

    // Store model name in reply property
    reply->setProperty("modelName", modelName);

    connect(reply, &QNetworkReply::finished, this, &AAFConnector::handleModelStatusReply);
    connect(reply, QOverload<QNetworkReply::NetworkError>::of(&QNetworkReply::errorOccurred),
            this, [this, reply](QNetworkReply::NetworkError error) {
                // Don't treat 404 as error during polling (model might not exist yet)
                if (error != QNetworkReply::ContentNotFoundError) {
                    handleNetworkError(error);
                }
                reply->deleteLater();
            });
}

void AAFConnector::handleModelStatusReply()
{
    QNetworkReply *reply = qobject_cast<QNetworkReply*>(sender());
    if (!reply) {
        qCWarning(lcConnector) << "handleModelStatusReply: reply is null";
        return;
    }

    QString modelName = reply->property("modelName").toString();
    qCDebug(lcConnector) << "HTTP status code:" << reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();

    if (reply->error() == QNetworkReply::NoError) {
        QByteArray data = reply->readAll();
        QJsonParseError parseError;
        QJsonDocument doc = QJsonDocument::fromJson(data, &parseError);

        if (parseError.error == QJsonParseError::NoError) {
            QJsonObject response = doc.object().value("data").toObject();
            ModelStatus status;
            status.name = modelName;
            status.id = response["id"].toString("unknown");
            status.description = response["description"].toString("unknown");
            status.ready = response["ready"].toBool(false);

            Q_EMIT modelStatusReceived(status);
            if (status.ready) {
                m_currentModelId = modelName;
                stopModelStatusPolling();
                Q_EMIT modelReady(modelName);
                Q_EMIT modelLoadCompleted(modelName);
            } else if (!status.ready) {
                // Calculate progress if available
                Q_EMIT modelStillLoading(modelName, 0);
            } else {
                qCWarning(lcConnector) << "Model status unclear";
            }
        } else {
            qCWarning(lcConnector) << "Failed to parse model status response:" << parseError.errorString();
        }
    } else if (reply->error() == QNetworkReply::ContentNotFoundError) {
        qCDebug(lcConnector) << "Model not found yet (still loading):" << modelName;
        Q_EMIT modelStillLoading(modelName, 0);
    } else {
        qCWarning(lcConnector) << "Model status request failed:" << reply->errorString();
    }

    reply->deleteLater();
}

#include "aafconnector.moc"
