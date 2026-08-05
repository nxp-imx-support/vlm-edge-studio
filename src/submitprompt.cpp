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
#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLoggingCategory>
#include <QRegularExpression>
#include <QUrl>

Q_LOGGING_CATEGORY(lcSubmitPrompt, "submit.prompt")

namespace {
    /**
     * @brief Remove file:// prefix from path if present
     */
    QString cleanFilePath(const QString& path) {
    // Use QUrl for correct file:// stripping; avoids heavyweight QRegularExpression.
    if (path.startsWith(QStringLiteral("file://")))
        return QUrl(path).toLocalFile();
    return path;
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
    , m_endpoint(0)
    , m_isLoadingModelList(true)
    , m_isLoadingModelListError()
    , m_isDownloadingModels(false)
    , m_downloadProgress(0)
    , m_hasDownloadError(false)
    , m_downloadProcess(nullptr)
    , m_currentDownloadIndex(0)
    , m_aafConnector(new AAFConnector(this)) // Qt parent-child ownership
{
    m_modelsToDownload = QStringList()
      << "nxp/Qwen2.5-VL-7B-Instruct-Ara240";

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

    connect(m_aafConnector, &AAFConnector::devicesReceived,
            this, [this](const QStringList &names) {
            qCDebug(lcSubmitPrompt) << "Endpoints populated:" << names;
            m_endpointNames = names;
            Q_EMIT endpointNamesChanged();
            });

    // Initialize connection and fetch devices once
    m_aafConnector->connectToServer();
    m_aafConnector->requestDevices();
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
                           << "Video:" << selectedModel.supportsVideo
                           << "Endpoint:" << m_activeEndpoint
                           << "Device:" << m_endpoint;

    clearOutputDisplay();

    if (!m_isModelLoaded) {
        setInferenceMetrics(selectedModel.description);
    }

    Q_EMIT selectedModelIndexChanged();

    // Load llm_params baseline then overlay per-model generation config
    loadLlmParamsFromConfig(AAFConfig::CONFIG_PATH);
    loadLlmParamsFromModelConfig(m_availableModels[index].name);
}

void SubmitPrompt::setLoadModel(bool load) {
    if (m_shouldLoadModel == load) {
        return;
    }

    m_shouldLoadModel = load;

    if (m_shouldLoadModel && !m_isModelLoaded && isModelIndexValid(m_selectedModelIndex)) {
        clearOutputDisplay();
        const auto& selectedModel = m_availableModels[m_selectedModelIndex];
        m_aafConnector->loadModel(selectedModel, m_endpoint);
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

    // Reset llm_params to server_config.json baseline after model ejection
    loadLlmParamsFromConfig(AAFConfig::CONFIG_PATH);
    qCDebug(lcSubmitPrompt) << "llm_params reset to server_config baseline after eject";
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

    // Try to fetch a model
    loadDefaultModel();
}

void SubmitPrompt::loadDefaultModel() {
    qCDebug(lcSubmitPrompt) << "No models available - user can download manually";
    m_availableModels.clear();
    Q_EMIT availableModelsChanged();
}

// ═══════════════════════════════════════════════════════════════
// Prompt Processing
// ═══════════════════════════════════════════════════════════════

void SubmitPrompt::setUserPromptText(const QString& prompt) {
    updatePromptText(prompt);
    clearOutputDisplay();
    setProcessingInference(true);

    // Push current llm_params into the connector before each request
    m_aafConnector->setLlmParams(m_llmParams);

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

void SubmitPrompt::initializeEndpoint(int endpoint, const QString &group) {
  // Format and set the initial endpoint display string
  QString endpointName = formatEndpointName(endpoint, group);
  qCDebug(lcSubmitPrompt) << "Initial endpoint set to:" << m_activeEndpoint;

  if(m_activeEndpoint == endpointName && m_endpoint == endpoint) {
    return;
  }
  m_activeEndpoint = endpointName;
  m_endpoint = endpoint;
}

QStringList SubmitPrompt::endpointNames() const { return m_endpointNames; }
QVariantMap SubmitPrompt::llmParams() const { return m_llmParams; }
QVariantMap SubmitPrompt::defaultLlmParams() const { return m_defaultLlmParams; }

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

QString SubmitPrompt::formatEndpointName(int endpoint, const QString &group) const {
  // Format endpoint based on group type
  if (group == QLatin1String("all")) {
    return QStringLiteral("All");
  } else if (group == QLatin1String("usb")) {
    return QStringLiteral("USB");
  } else if (group == QLatin1String("pcie")) {
    return QStringLiteral("PCIe%1").arg(endpoint);
  }

  // Default formatting
  return QStringLiteral("PCIe%1").arg(endpoint);
}

// ============================================================================
// Fetch Models Methods
// ============================================================================

void SubmitPrompt::downloadMissingModels() {
  if (m_isDownloadingModels) {
    qCWarning(lcSubmitPrompt) << "Download already in progress";
    return;
  }

  qCDebug(lcSubmitPrompt) << "Starting manual model download...";

  // Reset state
  m_currentDownloadIndex = 0;
  setHasDownloadError(false);
  setIsDownloadingModels(true);
  setDownloadProgress(0);

  // Start downloading the first model
  downloadNextModel();
}

void SubmitPrompt::downloadNextModel() {
  // Check if all models are downloaded
  if (m_currentDownloadIndex >= m_modelsToDownload.size()) {
    qCDebug(lcSubmitPrompt) << "All models downloaded successfully";
    setDownloadStatus("All models downloaded successfully!");
    setIsDownloadingModels(false);
    setDownloadProgress(100);

    // Refresh the models list to pick up newly downloaded models
    QTimer::singleShot(500, this, &SubmitPrompt::refreshModelsList);
    Q_EMIT modelDownloadCompleted();
    return;
  }

  const QString &modelId = m_modelsToDownload[m_currentDownloadIndex];
  qCDebug(lcSubmitPrompt) << "Downloading model"
                          << (m_currentDownloadIndex + 1)
                          << "of" << m_modelsToDownload.size()
                          << ":" << modelId;

  setDownloadStatus(QString("Downloading %1 (%2/%3)...")
                        .arg(modelId)
                        .arg(m_currentDownloadIndex + 1)
                        .arg(m_modelsToDownload.size()));

  // Calculate progress based on model index
  int progressPerModel = 100 / m_modelsToDownload.size();
  int baseProgress = m_currentDownloadIndex * progressPerModel;
  setDownloadProgress(baseProgress);

  // Clean up previous process if exists
  if (m_downloadProcess) {
    m_downloadProcess->disconnect();
    m_downloadProcess->deleteLater();
  }

  // Create new process
  m_downloadProcess = new QProcess(this);

  // Connect signals
  connect(m_downloadProcess, &QProcess::readyReadStandardOutput,
          this, &SubmitPrompt::handleDownloadOutput);
  connect(m_downloadProcess, &QProcess::readyReadStandardError,
          this, &SubmitPrompt::handleDownloadOutput);
  connect(m_downloadProcess, 
          QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
          this, &SubmitPrompt::handleDownloadFinished);
  connect(m_downloadProcess, &QProcess::errorOccurred,
          this, &SubmitPrompt::handleDownloadError);

  // Prepare command: uvx --from /usr/share/python-wheels/fetch_models-1.0.0-py3-none-any.whl fetch_models
  QString program = "uvx";
  QStringList arguments;
  arguments << "--from"
            << "/usr/share/python-wheels/fetch_models-1.0.0-py3-none-any.whl"
            << "fetch_models"
            << "--repo-id" << modelId;

  qCDebug(lcSubmitPrompt) << "Running command:" << program << arguments.join(" ");

  // Start download process
  m_downloadProcess->start(program, arguments);
  if (!m_downloadProcess->waitForStarted(5000)) {
    qCWarning(lcSubmitPrompt) << "Failed to start download process";
    setDownloadStatus("Failed to start download process");
    setHasDownloadError(true);
    setIsDownloadingModels(false);
  }
}

void SubmitPrompt::handleDownloadFinished(int exitCode, QProcess::ExitStatus exitStatus) {
  // Guard against a stale signal arriving after cancelDownload() advanced the index
  if (m_currentDownloadIndex >= m_modelsToDownload.size()) {
    qCWarning(lcSubmitPrompt) << "handleDownloadFinished: index out of range, ignoring";
    return;
  }
  const QString &modelId = m_modelsToDownload[m_currentDownloadIndex];

  if (exitStatus == QProcess::NormalExit && exitCode == 0) {
    qCDebug(lcSubmitPrompt) << "Successfully downloaded:" << modelId;

    // Calculate progress
    int progressPerModel = 100 / m_modelsToDownload.size();
    int newProgress = (m_currentDownloadIndex + 1) * progressPerModel;
    setDownloadProgress(newProgress);

    // Move to next model
    m_currentDownloadIndex++;
    downloadNextModel();
  } else {
    qCWarning(lcSubmitPrompt) << "Failed to download model:" << modelId
                              << "Exit code:" << exitCode;

    QString errorOutput = m_downloadProcess->readAllStandardError();
    setDownloadStatus(QString("Failed to download %1: %2")
                          .arg(modelId)
                          .arg(errorOutput.isEmpty() ? "Unknown error" : errorOutput));
    setHasDownloadError(true);

    // Continue with next model (don't stop on error, like postinst)
    m_currentDownloadIndex++;
    downloadNextModel();
  }
}

void SubmitPrompt::handleDownloadError(QProcess::ProcessError error) {
  qCWarning(lcSubmitPrompt) << "Download process error:" << error;

  QString errorMsg;
  switch (error) {
    case QProcess::FailedToStart:
      errorMsg = "Failed to start download. Is 'uvx' installed?";
      break;
    case QProcess::Crashed:
      errorMsg = "Download process crashed";
      break;
    case QProcess::Timedout:
      errorMsg = "Download process timed out";
      break;
    default:
      errorMsg = "Download process error occurred";
      break;
  }

  setDownloadStatus(errorMsg);
  setHasDownloadError(true);
  setIsDownloadingModels(false);
}

void SubmitPrompt::handleDownloadOutput() {
  if (!m_downloadProcess) {
    return;
  }

  QRegularExpression re(R"(\b(\d{1,3})%\|)");
  QString output = m_downloadProcess->readAllStandardOutput();
  QString errorOutput = m_downloadProcess->readAllStandardError();

  if (!output.isEmpty()) {
    qCDebug(lcSubmitPrompt) << "Download output:" << output.trimmed();
    QRegularExpressionMatch match = re.match(output);
    if (match.hasMatch()) {
      int percent = match.captured(1).toInt();
      setDownloadProgress(percent);
    }
  }

  if (!errorOutput.isEmpty()) {
    qCDebug(lcSubmitPrompt) << "Download error output:" << errorOutput.trimmed();
    QRegularExpressionMatch match = re.match(errorOutput);
    if (match.hasMatch()) {
      int percent = match.captured(1).toInt();
      setDownloadProgress(percent);
    }
  }
}

void SubmitPrompt::cancelDownload() {
  if (!m_isDownloadingModels || !m_downloadProcess) {
    return;
  }

  qCDebug(lcSubmitPrompt) << "Cancelling download...";

  // Disconnect signals first so the finished handler does not try to advance
  // the download queue after we reset state below.
  m_downloadProcess->disconnect();

  // Reset state before killing so any re-entrant signal from kill() is a no-op
  setDownloadStatus("Download cancelled by user");
  setIsDownloadingModels(false);
  setDownloadProgress(0);
  // Set index past the end to make handleDownloadFinished a safe no-op
  m_currentDownloadIndex = m_modelsToDownload.size();

  // Kill asynchronously -- do not call waitForFinished on the main/UI thread.
  // The QProcess parent relationship ensures the OS process is reaped on destruction.
  m_downloadProcess->kill();
}

void SubmitPrompt::setIsDownloadingModels(const bool downloading){
  if (m_isDownloadingModels == downloading) {
    return;
  }
  m_isDownloadingModels = downloading;
  Q_EMIT isDownloadingModelsChanged();
}

void SubmitPrompt::setDownloadProgress(const int progress){
  if (m_downloadProgress == progress) {
    return;
  }
  m_downloadProgress = progress;
  Q_EMIT downloadProgressChanged();
}

void SubmitPrompt::setDownloadStatus(const QString &status){
  if (m_downloadStatus == status) {
    return;
  }
  m_downloadStatus = status;
  Q_EMIT downloadStatusChanged();
}

void SubmitPrompt::setHasDownloadError(const bool &error){
  if (m_hasDownloadError == error) {
    return;
  }
  m_hasDownloadError = error;
  Q_EMIT hasDownloadErrorChanged();
}

// ============================================================================
// llm_params - runtime configuration
// ============================================================================

void SubmitPrompt::setLlmParams(const QVariantMap &params) {
    if (m_llmParams == params) return;
    m_llmParams = params;
    Q_EMIT llmParamsChanged();
    qCDebug(lcSubmitPrompt) << "llm_params updated:"
        << "generate_max_tokens=" << m_llmParams.value("generate_max_tokens")
        << "temperature="         << m_llmParams.value("temperature")
        << "top_k="               << m_llmParams.value("top_k")
        << "top_p="               << m_llmParams.value("top_p");
}

void SubmitPrompt::loadLlmParamsFromConfig(const QString &configPath) {
    QFile file(configPath);
    if (!file.open(QIODevice::ReadOnly)) {
        qCWarning(lcSubmitPrompt) << "Cannot open config for llm_params:" << configPath;
        return;
    }
    const QJsonDocument doc = QJsonDocument::fromJson(file.readAll());
    file.close();

    const QJsonObject llmJson = doc.object().value("llm_params").toObject();
    if (llmJson.isEmpty()) {
        qCWarning(lcSubmitPrompt) << "llm_params section not found in" << configPath;
        return;
    }

    m_llmParams        = llmJson.toVariantMap();
    m_defaultLlmParams = m_llmParams;
    Q_EMIT llmParamsChanged();

    qCDebug(lcSubmitPrompt) << "Loaded llm_params from default config:"
        << "generate_max_tokens=" << m_llmParams.value("generate_max_tokens")
        << "temperature="         << m_llmParams.value("temperature")
        << "top_k="               << m_llmParams.value("top_k")
        << "top_p="               << m_llmParams.value("top_p");
}

void SubmitPrompt::loadLlmParamsFromModelConfig(const QString &modelName) {
    // Try /usr/share/llm/{model_name}/generation_config.json
    const QString path = QStringLiteral("%1/%2/generation_config.json")
                             .arg(AAFConfig::MODEL_PATH, modelName);

    QFile file(path);
    if (!file.open(QIODevice::ReadOnly)) {
        qCDebug(lcSubmitPrompt) << "No generation_config.json for" << modelName
                                << "- keeping server_config.json defaults";
        return;
    }

    qCDebug(lcSubmitPrompt) << "Loaded llm_params from" << path << "for model:" << modelName;

    const QJsonDocument doc = QJsonDocument::fromJson(file.readAll());
    file.close();

    const QJsonObject obj = doc.object();
    if (obj.isEmpty()) {
        qCWarning(lcSubmitPrompt) << "Empty generation_config.json for" << modelName;
        return;
    }

    // Build a merged map: start from the server_config baseline then overlay
    // the editable fields if present in generation_config.json.
    QVariantMap merged = m_defaultLlmParams;

    auto applyInt = [&](const QString &srcKey, const QString &dstKey) {
        if (obj.contains(srcKey))
            merged[dstKey] = obj.value(srcKey).toInt();
    };
    auto applyDouble = [&](const QString &srcKey, const QString &dstKey) {
        if (obj.contains(srcKey))
            merged[dstKey] = obj.value(srcKey).toDouble();
    };

    // Map generation_config.json field names to internal llm_params keys.
    // prefer max_new_tokens over max_length if both are present (more specific).
    applyInt   ("max_length",         "generate_max_tokens");
    applyInt   ("max_new_tokens",     "generate_max_tokens");
    applyDouble("temperature",        "temperature");
    applyInt   ("top_k",              "top_k");
    applyDouble("top_p",              "top_p");
    applyDouble("repetition_penalty", "repeat_penalty");

    m_llmParams        = merged;
    m_defaultLlmParams = merged;
    Q_EMIT llmParamsChanged();

    qCDebug(lcSubmitPrompt) << "Merged generation_config.json for" << modelName
        << "generate_max_tokens=" << m_llmParams.value("generate_max_tokens")
        << "temperature="         << m_llmParams.value("temperature")
        << "top_k="               << m_llmParams.value("top_k")
        << "top_p="               << m_llmParams.value("top_p");
}

void SubmitPrompt::refreshModelsList() {
  if (!m_aafConnector) {
    qCWarning(lcSubmitPrompt) << "Cannot refresh: AAFConnector is null";
    return;
  }

  qCDebug(lcSubmitPrompt) << "Refreshing models list from config...";
  m_aafConnector->loadModelsFromConfig(AAFConfig::CONFIG_PATH);
}