/*
 * Copyright 2025-2026 NXP
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

#ifndef CAMERADETECTOR_H
#define CAMERADETECTOR_H

#include <QObject>
#include <QString>
#include <QStringList>
#include <QTimer>
#include <QFileSystemWatcher>
#include <QList>

struct CameraInfo {
    QString devicePath;        // e.g., "/dev/video0"
    QString name;             // Camera name from driver
    QString driver;           // Driver name
    QString busInfo;          // Bus information
    QString card;             // Card description
    QStringList supportedFormats; // Supported pixel formats
    QStringList supportedResolutions; // Supported resolutions
    bool isCapture;           // True if it's a capture device
    int deviceIndex;          // Index number (0, 1, 2, etc.)
};

class CameraDetector : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QStringList availableCameras READ availableCameras NOTIFY camerasChanged)
    Q_PROPERTY(QString selectedCamera READ selectedCamera WRITE setSelectedCamera NOTIFY selectedCameraChanged)
    Q_PROPERTY(int selectedCameraIndex READ selectedCameraIndex WRITE setSelectedCameraIndex NOTIFY selectedCameraIndexChanged)

public:
    explicit CameraDetector(QObject *parent = nullptr);
    ~CameraDetector();

    // Property getters
    QStringList availableCameras() const;
    QString selectedCamera() const;
    int selectedCameraIndex() const;

    // Property setters
    void setSelectedCamera(const QString& devicePath);
    void setSelectedCameraIndex(int index);

    // Public methods
    Q_INVOKABLE void refreshCameras();
    Q_INVOKABLE QString getCameraDescription(const QString& devicePath) const;
    Q_INVOKABLE QStringList getSupportedResolutions(const QString& devicePath) const;
    Q_INVOKABLE bool isCameraAvailable(const QString& devicePath) const;
    
    // Get detailed camera info
    const QList<CameraInfo>& getCameraInfoList() const { return m_cameraInfoList; }
    CameraInfo getCameraInfo(const QString& devicePath) const;

public Q_SLOTS:
    void startAutoRefresh(int intervalMs = 5000);
    void stopAutoRefresh();

Q_SIGNALS:
    void camerasChanged();
    void selectedCameraChanged();
    void selectedCameraIndexChanged();
    void cameraConnected(const QString& devicePath);
    void cameraDisconnected(const QString& devicePath);

private Q_SLOTS:
    void onDeviceChanged();
    void periodicRefresh();

private:
    void detectCameras();
    bool queryDeviceInfo(const QString& devicePath, CameraInfo& info);
    QStringList getPixelFormats(int fd);
    QStringList getResolutions(int fd);
    QString formatToString(uint32_t format);
    bool isVideoCaptureDevice(int fd);

    QList<CameraInfo> m_cameraInfoList;
    QStringList m_availableCameras;
    QString m_selectedCamera;
    int m_selectedCameraIndex;
    
    QFileSystemWatcher* m_deviceWatcher;
    QTimer* m_refreshTimer;
    
    static constexpr int MAX_VIDEO_DEVICES = 64;
};

#endif // CAMERADETECTOR_H