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

#ifndef SUBMITPROMPT_H
#define SUBMITPROMPT_H

#include <QList>
#include <QObject>
#include <QString>
#include <QStringList>
#include "aafconnector.h"

namespace SubmitPromptConfig {
    // Media type identifiers
    inline const QString MEDIA_TYPE_IMAGE = QStringLiteral("image");
    inline const QString MEDIA_TYPE_VIDEO = QStringLiteral("video");
    inline const QString MEDIA_TYPE_TEXT = QStringLiteral("text");

    // Default prompts
    inline const QString DEFAULT_IMAGE_PROMPT = QStringLiteral("Describe the Image");
    inline const QString DEFAULT_VIDEO_PROMPT = QStringLiteral("Describe the Video");

    // Default paths
    inline const QString DEFAULT_IMAGE_PATH = QStringLiteral("/usr/share/vlm-edge-studio/assets/images/image.jpg");
    inline const QString DEFAULT_VIDEO_PATH = QStringLiteral("/usr/share/vlm-edge-studio/assets/videos/video.mp4");
    inline const QString DEFAULT_ENDPOINT = QStringLiteral("PCIe0");
}

/**
 * @brief Main controller for VLM prompt submission and model management
 *
 * This class manages the interaction between the UI and the AI model backend,
 * handling model loading, media input processing, and response streaming.
 */
class SubmitPrompt : public QObject {
    Q_OBJECT

    // Input/Output Properties
    Q_PROPERTY(QString userPromptText READ userPromptText WRITE setUserPromptText
               NOTIFY userPromptTextChanged FINAL)
    Q_PROPERTY(QString modelResponseText READ modelResponseText
               NOTIFY modelResponseTextChanged FINAL)
    Q_PROPERTY(QString inferenceMetrics READ inferenceMetrics
               NOTIFY inferenceMetricsChanged FINAL)

    // Media Input Properties
    Q_PROPERTY(QString imageSourcePath READ imageSourcePath WRITE setImageSourcePath
               NOTIFY imageSourcePathChanged FINAL)
    Q_PROPERTY(QString videoSourcePath READ videoSourcePath WRITE setVideoSourcePath
               NOTIFY videoSourcePathChanged FINAL)
    Q_PROPERTY(QString activeMediaType READ activeMediaType WRITE setActiveMediaType
               NOTIFY activeMediaTypeChanged FINAL)

    // Processing State Properties
    Q_PROPERTY(bool isProcessingInference READ isProcessingInference
               NOTIFY isProcessingInferenceChanged FINAL)
    Q_PROPERTY(bool isLoadingMedia READ isLoadingMedia WRITE setLoadingMedia
               NOTIFY isLoadingMediaChanged FINAL)
    Q_PROPERTY(bool canSubmitPrompt READ canSubmitPrompt
               NOTIFY canSubmitPromptChanged FINAL)

    // Model Management Properties
    Q_PROPERTY(int selectedModelIndex READ selectedModelIndex WRITE setCurrentModelIndex
               NOTIFY selectedModelIndexChanged FINAL)
    Q_PROPERTY(QString selectedModelName READ selectedModelName
               NOTIFY selectedModelIndexChanged FINAL)
    Q_PROPERTY(QString selectedModelDescription READ selectedModelDescription
               NOTIFY selectedModelIndexChanged FINAL)
    Q_PROPERTY(QString selectedModelType READ selectedModelType
               NOTIFY selectedModelIndexChanged FINAL)
    Q_PROPERTY(bool modelSupportsImage READ modelSupportsImage
               NOTIFY selectedModelIndexChanged FINAL)
    Q_PROPERTY(bool modelSupportsVideo READ modelSupportsVideo
               NOTIFY selectedModelIndexChanged FINAL)

    // Model Loading Properties
    Q_PROPERTY(bool shouldLoadModel READ shouldLoadModel WRITE setLoadModel
               NOTIFY shouldLoadModelChanged FINAL)
    Q_PROPERTY(bool isModelLoaded READ isModelLoaded NOTIFY isModelLoadedChanged FINAL)
    Q_PROPERTY(int modelLoadingProgress READ modelLoadingProgress WRITE setModelLoadProgress
               NOTIFY modelLoadingProgressChanged FINAL)
    Q_PROPERTY(int modelLoadingDuration READ modelLoadingDuration CONSTANT)

    // Model List Properties
    Q_PROPERTY(bool isLoadingModelList READ isLoadingModelList NOTIFY isLoadingModelListChanged FINAL)
    Q_PROPERTY(QString isLoadingModelListError READ isLoadingModelListError
               NOTIFY isLoadingModelListErrorChanged FINAL)

    // Endpoint Configuration
    Q_PROPERTY(QString activeEndpoint READ activeEndpoint WRITE setActiveEndpoint
               NOTIFY activeEndpointChanged FINAL)

public:
    explicit SubmitPrompt(QObject* parent = nullptr);
    ~SubmitPrompt() override;

    // Disable copy and move
    SubmitPrompt(const SubmitPrompt&) = delete;
    SubmitPrompt& operator=(const SubmitPrompt&) = delete;
    SubmitPrompt(SubmitPrompt&&) = delete;
    SubmitPrompt& operator=(SubmitPrompt&&) = delete;

    // Invokable methods for QML
    Q_INVOKABLE void cancelInference();
    Q_INVOKABLE void ejectModel();
    Q_INVOKABLE QStringList availableModelNames() const;
    Q_INVOKABLE void clearOutputDisplay();
    Q_INVOKABLE void killConnectorProcess();

    // Getters
    QString userPromptText() const { return m_userPromptText; }
    QString modelResponseText() const { return m_modelResponseText; }
    QString inferenceMetrics() const { return m_inferenceMetrics; }
    QString imageSourcePath() const { return m_imageSourcePath; }
    QString videoSourcePath() const { return m_videoSourcePath; }
    QString activeMediaType() const { return m_activeMediaType; }
    QString activeEndpoint() const { return m_activeEndpoint; }

    bool isProcessingInference() const { return m_isProcessingInference; }
    bool isLoadingMedia() const { return m_isLoadingMedia; }
    bool canSubmitPrompt() const { return m_canSubmitPrompt; }
    bool shouldLoadModel() const { return m_shouldLoadModel; }
    bool isModelLoaded() const { return m_isModelLoaded; }
    bool isLoadingModelList() const { return m_isLoadingModelList; }

    int selectedModelIndex() const { return m_selectedModelIndex; }
    int modelLoadingProgress() const { return m_modelLoadingProgress; }
    int modelLoadingDuration() const { return m_modelLoadingDuration; }

    QString selectedModelName() const;
    QString selectedModelDescription() const;
    QString selectedModelType() const;
    QString isLoadingModelListError() const { return m_isLoadingModelListError; }

    bool modelSupportsImage() const;
    bool modelSupportsVideo() const;

Q_SIGNALS:
    // Input/Output signals
    void userPromptTextChanged();
    void modelResponseTextChanged();
    void inferenceMetricsChanged();

    // Media signals
    void imageSourcePathChanged();
    void videoSourcePathChanged();
    void activeMediaTypeChanged();

    // Processing state signals
    void isProcessingInferenceChanged();
    void isLoadingMediaChanged();
    void canSubmitPromptChanged();
    void inferenceStopRequested();

    // Model management signals
    void selectedModelIndexChanged();
    void shouldLoadModelChanged();
    void isModelLoadedChanged();
    void modelLoadingProgressChanged();

    // Model list signals
    void isLoadingModelListChanged();
    void isLoadingModelListErrorChanged();
    void availableModelsChanged();

    // Configuration signals
    void activeEndpointChanged();

public Q_SLOTS:
    // Setters
    void setUserPromptText(const QString& prompt);
    void setImageSourcePath(const QString& path);
    void setVideoSourcePath(const QString& path);
    void setActiveMediaType(const QString& type);
    void setActiveEndpoint(const QString& endpoint);
    void setCurrentModelIndex(int index);
    void setLoadModel(bool load);
    void setModelLoadProgress(int progress);
    void setLoadingMedia(bool progress);

    // Internal setters
    void setProcessingInference(bool processing);
    void setModelLoaded(bool loaded);

    // Response handlers
    void handleInferenceResponse(const QString& response);
    void handleInferenceError(const QString& error);

    // Model list handlers
    void handleModelListReceived(const QList<AAFConnector::ModelInfo>& models);
    void handleModelListError(const QString& error);

    // Recording handler
    void handleRecordingComplete(const QString& videoPath);

private:
    // Helper methods
    void resetToDefault();
    void loadDefaultModel();
    void updatePromptText(const QString& prompt);
    bool isModelIndexValid(int index) const;
    QString formatModelName(const QString& modelName) const;

    void setModelResponseText(const QString& text);
    void setInferenceMetrics(const QString& metrics);

    // Input/Output state
    QString m_userPromptText;
    QString m_modelResponseText;
    QString m_inferenceMetrics;

    // Media paths
    QString m_imageSourcePath;
    QString m_videoSourcePath;
    QString m_activeMediaType;
    QString m_activeEndpoint;

    // Processing state
    bool m_isProcessingInference;
    bool m_isLoadingMedia;
    bool m_canSubmitPrompt;

    // Model state
    int m_selectedModelIndex;
    bool m_shouldLoadModel;
    bool m_isModelLoaded;
    int m_modelLoadingProgress;

    // Model list state
    bool m_isLoadingModelList;
    QString m_isLoadingModelListError;
    QStringList m_availableModelNames;
    QList<AAFConnector::ModelInfo> m_availableModels;

    // Constants
    static constexpr int m_modelLoadingDuration = 476000; // 476 seconds (~7.9 min)

    // Backend connector
    AAFConnector* m_aafConnector;
};

#endif // SUBMITPROMPT_H