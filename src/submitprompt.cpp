/*
 * Copyright 2024-2026 NXP
 *
 * NXP Proprietary. This software is owned or controlled by NXP and may only be
 * used strictly in accordance with the applicable license terms.  By expressly
 * accepting such terms or by downloading, installing, activating and/or
 * otherwise using the software, you are agreeing that you have read, and that
 * you agree to comply with and are bound by, such license terms.  If you do
 * not agree to be bound by the applicable license terms, then you may not
 * retain, install, activate or otherwise use the software.
 */

#include "submitprompt.h"
#include <QLoggingCategory>
#include <QProcess>
#include <QRegularExpression>

Q_LOGGING_CATEGORY(lcSubmitPrompt, "submit.prompt")

namespace {
    /**
     * @brief Remove file:// prefix from path if present
     */
    QString cleanFilePath(const QString& path) {
        QString cleaned = path;
        cleaned.replace(QRegularExpression("^file://"), "");
        return cleaned;
    }
}

using namespace SubmitPromptConfig;

SubmitPrompt::SubmitPrompt(QObject *parent)
    : QObject(parent)
    , m_userPromptText(DEFAULT_VIDEO_PROMPT)
    , m_modelResponseText()
    , m_inferenceMetrics()
    , m_imageSourcePath(QString("file://") + DEFAULT_IMAGE_PATH)
    , m_videoSourcePath(DEFAULT_VIDEO_PATH)
    , m_activeMediaType()
    , m_activeEndpoint(DEFAULT_ENDPOINT)
    , m_isProcessingInference(false)
    , m_isLoadingMedia(false)
    , m_canSubmitPrompt(true)
    , m_selectedModelIndex(-1)
    , m_shouldLoadModel(false)
    , m_isModelLoaded(false)
    , m_modelLoadingProgress(0)
    , m_isLoadingModelList(true)
    , m_isLoadingModelListError()
    , m_aafConnector(new AAFConnector(this)) // Qt parent-child ownership
{
    // Connect model list signals
    connect(m_aafConnector, &AAFConnector::modelsListReceived,
            this, &SubmitPrompt::handleModelListReceived);
    connect(m_aafConnector, &AAFConnector::modelsListError,
            this, &SubmitPrompt::handleModelListError);

    // Connect inference signals
    connect(m_aafConnector, &AAFConnector::responseReceived,
            this, &SubmitPrompt::handleInferenceResponse);
    connect(m_aafConnector, &AAFConnector::errorOccurred,
            this, &SubmitPrompt::handleInferenceError);
    connect(m_aafConnector, &AAFConnector::tokenReceived,
            this, &SubmitPrompt::setModelResponseText);
    connect(m_aafConnector, &AAFConnector::metricsReceived,
            this, &SubmitPrompt::setInferenceMetrics);

    // Connect processing state signals
    connect(m_aafConnector, &AAFConnector::requestStarted,
            this, [this]() { setProcessingInference(true); });
    connect(m_aafConnector, &AAFConnector::requestFinished,
            this, [this]() { setProcessingInference(false); });

    // Connect model loading signals
    connect(m_aafConnector, &AAFConnector::modelLoadStarted,
            this, [this](const QString& modelName) {
                qCDebug(lcSubmitPrompt) << "Model load started:" << modelName;
                setInferenceMetrics("Loading model in progress...");
                setLoadModel(true);
            });

    connect(m_aafConnector, &AAFConnector::modelLoadCompleted,
            this, [this](const QString& modelName) {
                qCDebug(lcSubmitPrompt) << "Model load completed:" << modelName;
                setInferenceMetrics(QString());
                setModelLoaded(true);
                setLoadModel(false);
            });

    connect(m_aafConnector, &AAFConnector::modelReady,
            this, [this](const QString& modelName) {
                qCDebug(lcSubmitPrompt) << "Model ready:" << modelName;
                setInferenceMetrics(QString());
                setModelLoaded(true);
                setLoadModel(false);
            });

    connect(m_aafConnector, &AAFConnector::modelOperationError,
            this, [this](const QString& error) {
                qCWarning(lcSubmitPrompt) << "Model operation error:" << error;
                setModelLoadProgress(0);
                setLoadModel(false);
                setModelLoaded(false);
            });

    // Initialize connection
    m_aafConnector->connectToServer();
}

SubmitPrompt::~SubmitPrompt() = default;

// ═══════════════════════════════════════════════════════════════
// Model Management
// ═══════════════════════════════════════════════════════════════

QStringList SubmitPrompt::availableModelNames() const {
    return m_availableModelNames;
}

QString SubmitPrompt::selectedModelName() const {
    if (isModelIndexValid(m_selectedModelIndex)) {
        return m_availableModelNames[m_selectedModelIndex];
    }
    return QStringLiteral("Unknown");
}

QString SubmitPrompt::selectedModelDescription() const {
    if (isModelIndexValid(m_selectedModelIndex)) {
        return m_availableModels[m_selectedModelIndex].description;
    }
    return QStringLiteral("No model selected");
}

QString SubmitPrompt::selectedModelType() const {
    if (isModelIndexValid(m_selectedModelIndex)) {
        return m_availableModels[m_selectedModelIndex].type;
    }
    return QStringLiteral("unknown");
}

bool SubmitPrompt::modelSupportsImage() const {
    if (isModelIndexValid(m_selectedModelIndex)) {
        return m_availableModels[m_selectedModelIndex].supportsImage;
    }
    return false;
}

bool SubmitPrompt::modelSupportsVideo() const {
    if (isModelIndexValid(m_selectedModelIndex)) {
        return m_availableModels[m_selectedModelIndex].supportsVideo;
    }
    return false;
}

void SubmitPrompt::setCurrentModelIndex(int index) {
    if (m_selectedModelIndex == index) {
        return;
    }

    if (!isModelIndexValid(index)) {
        qCWarning(lcSubmitPrompt) << "Invalid model index:" << index;
        return;
    }

    if (m_isProcessingInference) {
        qCWarning(lcSubmitPrompt) << "Cannot change model while processing";
        return;
    }

    m_selectedModelIndex = index;
    const auto& selectedModel = m_availableModels[index];

    qCDebug(lcSubmitPrompt) << "Switching to model:" << selectedModel.name
                           << "Type:" << selectedModel.type
                           << "Image:" << selectedModel.supportsImage
                           << "Video:" << selectedModel.supportsVideo;

    clearOutputDisplay();

    if (!m_isModelLoaded) {
        setInferenceMetrics(selectedModel.description);
    }

    Q_EMIT selectedModelIndexChanged();
}

void SubmitPrompt::setLoadModel(bool load) {
    if (m_shouldLoadModel == load) {
        return;
    }

    m_shouldLoadModel = load;

    if (m_shouldLoadModel && !m_isModelLoaded && isModelIndexValid(m_selectedModelIndex)) {
        clearOutputDisplay();
        const auto& selectedModel = m_availableModels[m_selectedModelIndex];
        m_aafConnector->loadModel(selectedModel);
    }

    Q_EMIT shouldLoadModelChanged();
}

void SubmitPrompt::setModelLoaded(bool loaded) {
    if (m_isModelLoaded == loaded) {
        return;
    }

    m_isModelLoaded = loaded;

    if (m_isModelLoaded && isModelIndexValid(m_selectedModelIndex)) {
        const auto& model = m_availableModels[m_selectedModelIndex];

        // Set default mode based on capabilities (priority: Image > Video > Text)
        QString defaultMode;
        if (model.supportsImage) {
            defaultMode = MEDIA_TYPE_IMAGE;
        } else if (model.supportsVideo) {
            defaultMode = MEDIA_TYPE_VIDEO;
        } else {
            defaultMode = MEDIA_TYPE_TEXT;
        }

        setInferenceMetrics(QString());
        setActiveMediaType(defaultMode);
    } else {
        setActiveMediaType(QString());
    }

    Q_EMIT isModelLoadedChanged();
}

void SubmitPrompt::setModelLoadProgress(int progress) {
    const int clampedProgress = qBound(0, progress, 100);

    if (m_modelLoadingProgress == clampedProgress) {
        return;
    }

    m_modelLoadingProgress = clampedProgress;
    qCDebug(lcSubmitPrompt) << "Model load progress:" << m_modelLoadingProgress << "%";
    Q_EMIT modelLoadingProgressChanged();
}

void SubmitPrompt::ejectModel() {
    if (!m_isModelLoaded || !isModelIndexValid(m_selectedModelIndex)) {
        return;
    }

    const auto& selectedModel = m_availableModels[m_selectedModelIndex];
    m_aafConnector->removeModel(selectedModel.name);
    setModelLoaded(false);
    clearOutputDisplay();
}

// ═══════════════════════════════════════════════════════════════
// Model List Handling
// ═══════════════════════════════════════════════════════════════

void SubmitPrompt::handleModelListReceived(const QList<AAFConnector::ModelInfo>& models) {
    m_availableModels = models;
    m_availableModelNames.clear();
    m_availableModelNames.reserve(models.size());

    for (const auto& model : models) {
        const QString displayName = formatModelName(model.name);
        m_availableModelNames.append(displayName);

        qCDebug(lcSubmitPrompt) << "Model:" << model.name
                               << "Display:" << displayName
                               << "Type:" << model.type
                               << "Image:" << model.supportsImage
                               << "Video:" << model.supportsVideo;
    }

    m_isLoadingModelList = false;
    Q_EMIT isLoadingModelListChanged();
    Q_EMIT availableModelsChanged();

    if (!m_availableModels.isEmpty()) {
        setCurrentModelIndex(0);
    } else {
        qCWarning(lcSubmitPrompt) << "No enabled models found!";
        m_isLoadingModelListError = QStringLiteral("No enabled models in configuration");
        Q_EMIT isLoadingModelListErrorChanged();
    }
}

void SubmitPrompt::handleModelListError(const QString& error) {
    qCWarning(lcSubmitPrompt) << "Failed to load models:" << error;

    m_isLoadingModelList = false;
    m_isLoadingModelListError = error;

    Q_EMIT isLoadingModelListChanged();
    Q_EMIT isLoadingModelListErrorChanged();

    // Fallback model
    loadDefaultModel();
}

void SubmitPrompt::loadDefaultModel() {
    qCDebug(lcSubmitPrompt) << "Loading fallback model";

    m_availableModelNames.clear();
    m_availableModelNames << QStringLiteral("Qwen 2.5 VL 7B Instruct (Fallback)");

    AAFConnector::ModelInfo fallbackModel;
    fallbackModel.name = QStringLiteral("Qwen2.5-vl-7B-Instruct");
    fallbackModel.description = QStringLiteral("Qwen2.5-VL 7B instance with vision and language capabilities.");
    fallbackModel.type = QStringLiteral("qwen_vl_video");
    fallbackModel.enabled = true;
    fallbackModel.supportsVideo = true;
    fallbackModel.supportsImage = true;

    m_availableModels.clear();
    m_availableModels.append(fallbackModel);

    Q_EMIT availableModelsChanged();
    setCurrentModelIndex(0);
}

QString SubmitPrompt::formatModelName(const QString& modelName) const {
    QString formatted = modelName;
    formatted.replace('-', ' ').replace('_', '.');
    formatted.replace(QStringLiteral("vl"), QStringLiteral("Video"), Qt::CaseInsensitive);

    QStringList words = formatted.split(' ', Qt::SkipEmptyParts);

    for (QString& word : words) {
        // Capitalize first letter
        if (!word.isEmpty() && word[0].isLetter()) {
            word[0] = word[0].toUpper();
        }

        // Handle patterns like "7b" -> "7B"
        static const QRegularExpression sizePattern(R"(^(\d+)([a-z])$)");
        const auto match = sizePattern.match(word);
        if (match.hasMatch()) {
            word = match.captured(1) + match.captured(2).toUpper();
        }
    }

    return words.join(' ');
}

// ═══════════════════════════════════════════════════════════════
// Prompt Processing
// ═══════════════════════════════════════════════════════════════

void SubmitPrompt::setUserPromptText(const QString& prompt) {
    updatePromptText(prompt);
    clearOutputDisplay();
    setProcessingInference(true);

    if (m_activeMediaType == MEDIA_TYPE_IMAGE) {
        qCDebug(lcSubmitPrompt) << "Sending IMAGE analysis request:" << m_imageSourcePath;
        m_aafConnector->sendVisionPrompt(m_userPromptText, m_imageSourcePath, MEDIA_TYPE_IMAGE);
    } else if (m_activeMediaType == MEDIA_TYPE_VIDEO) {
        qCDebug(lcSubmitPrompt) << "Sending VIDEO analysis request:" << m_videoSourcePath;
        m_aafConnector->sendVisionPrompt(m_userPromptText, m_videoSourcePath, MEDIA_TYPE_VIDEO);
    } else {
        qCWarning(lcSubmitPrompt) << "Unknown media type:" << m_activeMediaType;
        setProcessingInference(false);
    }
}

void SubmitPrompt::updatePromptText(const QString& prompt) {
    if (m_userPromptText == prompt) {
        return;
    }

    m_userPromptText = prompt;
    Q_EMIT userPromptTextChanged();
}

void SubmitPrompt::setProcessingInference(bool processing) {
    if (m_isProcessingInference == processing) {
        return;
    }

    m_isProcessingInference = processing;
    Q_EMIT isProcessingInferenceChanged();
}

void SubmitPrompt::setLoadingMedia(bool progress) {
    if (m_isLoadingMedia == progress) {
        return;
    }

    m_isLoadingMedia = progress;
    Q_EMIT isLoadingMediaChanged();
}

void SubmitPrompt::cancelInference() {
    Q_EMIT inferenceStopRequested();
}

// ═══════════════════════════════════════════════════════════════
// Response Handling
// ═══════════════════════════════════════════════════════════════

void SubmitPrompt::handleInferenceResponse(const QString& response) {
    qCDebug(lcSubmitPrompt) << "Received response from agent";

    m_modelResponseText = response;
    Q_EMIT modelResponseTextChanged();
    setProcessingInference(false);
}

void SubmitPrompt::handleInferenceError(const QString& error) {
    m_modelResponseText = QStringLiteral("Error: ") + error;
    Q_EMIT modelResponseTextChanged();
    setProcessingInference(false);
}

void SubmitPrompt::setModelResponseText(const QString& token) {
    m_modelResponseText += token;
    Q_EMIT modelResponseTextChanged();
}

void SubmitPrompt::setInferenceMetrics(const QString& metrics) {
    if (m_inferenceMetrics == metrics) {
        return;
    }

    m_inferenceMetrics = metrics;
    Q_EMIT inferenceMetricsChanged();
}

// ═══════════════════════════════════════════════════════════════
// Media Input Handling
// ═══════════════════════════════════════════════════════════════

void SubmitPrompt::setImageSourcePath(const QString& path) {
    const QString cleanPath = cleanFilePath(path);

    if (m_imageSourcePath == cleanPath) {
        return;
    }

    clearOutputDisplay();

    qCDebug(lcSubmitPrompt) << "Source image path:" << cleanPath;

    m_imageSourcePath = cleanPath;
    Q_EMIT imageSourcePathChanged();

    updatePromptText(DEFAULT_IMAGE_PROMPT);
}

void SubmitPrompt::setVideoSourcePath(const QString& path) {
    if (m_videoSourcePath == path) {
        return;
    }

    qCDebug(lcSubmitPrompt) << "Source video path:" << path;
    clearOutputDisplay();

    m_videoSourcePath = path;
    Q_EMIT videoSourcePathChanged();

    updatePromptText(DEFAULT_VIDEO_PROMPT);
}

void SubmitPrompt::setActiveMediaType(const QString& type) {
    if (m_activeMediaType == type) {
        return;
    }

    qCDebug(lcSubmitPrompt) << "Media type changed to:" << type;
    m_activeMediaType = type;

    if (m_activeMediaType == MEDIA_TYPE_IMAGE) {
        updatePromptText(DEFAULT_IMAGE_PROMPT);
    } else if (m_activeMediaType == MEDIA_TYPE_VIDEO) {
        updatePromptText(DEFAULT_VIDEO_PROMPT);
    }

    Q_EMIT activeMediaTypeChanged();
}

void SubmitPrompt::handleRecordingComplete(const QString& videoPath) {
    qCDebug(lcSubmitPrompt) << "Recording finished:" << videoPath;
    setVideoSourcePath(videoPath);
}

// ═══════════════════════════════════════════════════════════════
// Configuration
// ═══════════════════════════════════════════════════════════════

void SubmitPrompt::setActiveEndpoint(const QString& endpoint) {
    if (m_activeEndpoint == endpoint) {
        return;
    }

    qCDebug(lcSubmitPrompt) << "Endpoint changed to:" << endpoint;
    m_activeEndpoint = endpoint;
    Q_EMIT activeEndpointChanged();
}

// ═══════════════════════════════════════════════════════════════
// Utility Methods
// ═══════════════════════════════════════════════════════════════

void SubmitPrompt::clearOutputDisplay() {
    m_modelResponseText.clear();
    Q_EMIT modelResponseTextChanged();

    m_inferenceMetrics.clear();
    Q_EMIT inferenceMetricsChanged();
}

bool SubmitPrompt::isModelIndexValid(int index) const {
    return index >= 0 && index < m_availableModels.size();
}

void SubmitPrompt::killConnectorProcess() {
    QProcess::execute("pkill", QStringList() << "connector");
}