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

#include "cameradetector.h"
#include <QDebug>
#include <QDir>
#include <QFileInfo>
#include <QLoggingCategory>

#include <fcntl.h>
#include <unistd.h>
#include <sys/ioctl.h>
#include <linux/videodev2.h>
#include <errno.h>
#include <cstring>

Q_LOGGING_CATEGORY(lcCameraDetector, "camera.detector")

CameraDetector::CameraDetector(QObject *parent)
    : QObject(parent)
    , m_selectedCameraIndex(-1)
    , m_deviceWatcher(nullptr)
    , m_refreshTimer(new QTimer(this))
{
    // Set up file system watcher for /dev directory
    m_deviceWatcher = new QFileSystemWatcher(this);
    m_deviceWatcher->addPath("/dev");
    
    connect(m_deviceWatcher, &QFileSystemWatcher::directoryChanged,
            this, &CameraDetector::onDeviceChanged);
    
    // Set up periodic refresh timer
    m_refreshTimer->setSingleShot(false);
    connect(m_refreshTimer, &QTimer::timeout,
            this, &CameraDetector::periodicRefresh);
    
    // Initial camera detection
    refreshCameras();
}

CameraDetector::~CameraDetector()
{
    stopAutoRefresh();
}

QStringList CameraDetector::availableCameras() const
{
    return m_availableCameras;
}

QString CameraDetector::selectedCamera() const
{
    return m_selectedCamera;
}

int CameraDetector::selectedCameraIndex() const
{
    return m_selectedCameraIndex;
}

void CameraDetector::setSelectedCamera(const QString& devicePath)
{
    if (m_selectedCamera != devicePath) {
        m_selectedCamera = devicePath;
        
        // Update index
        int newIndex = -1;
        for (int i = 0; i < m_availableCameras.size(); ++i) {
            if (m_availableCameras[i].contains(devicePath)) {
                newIndex = i;
                break;
            }
        }
        
        if (m_selectedCameraIndex != newIndex) {
            m_selectedCameraIndex = newIndex;
            Q_EMIT selectedCameraIndexChanged();
        }
        
        Q_EMIT selectedCameraChanged();
        qCDebug(lcCameraDetector) << "Selected camera changed to:" << devicePath;
    }
}

void CameraDetector::setSelectedCameraIndex(int index)
{
    if (index >= 0 && index < m_cameraInfoList.size() &&
    m_selectedCameraIndex != index) {
        m_selectedCameraIndex = index;
        m_selectedCamera = m_cameraInfoList[index].devicePath;
        
        Q_EMIT selectedCameraIndexChanged();
        Q_EMIT selectedCameraChanged();
        qCDebug(lcCameraDetector) << "Selected camera index changed to:" << index;
    }
}

void CameraDetector::refreshCameras()
{
    qCDebug(lcCameraDetector) << "Refreshing camera list...";
    
    auto previousCameras = m_availableCameras;
    detectCameras();
    
    // Check for newly connected or disconnected cameras
    for (const auto& camera : m_availableCameras) {
        if (!previousCameras.contains(camera)) {
            QString devicePath = camera.split(" - ").first();
            Q_EMIT cameraConnected(devicePath);
        }
    }
    
    for (const auto& camera : previousCameras) {
        if (!m_availableCameras.contains(camera)) {
            QString devicePath = camera.split(" - ").first();
            Q_EMIT cameraDisconnected(devicePath);
        }
    }
    
    // Validate current selection
    if (!m_selectedCamera.isEmpty() && !isCameraAvailable(m_selectedCamera)) {
        qCDebug(lcCameraDetector) << "Previously selected camera" << m_selectedCamera << "is no longer available";
        m_selectedCamera.clear();
        m_selectedCameraIndex = -1;
        Q_EMIT selectedCameraChanged();
        Q_EMIT selectedCameraIndexChanged();
    }
    
    Q_EMIT camerasChanged();
}

void CameraDetector::detectCameras()
{
    m_cameraInfoList.clear();
    m_availableCameras.clear();
    
    // Scan for video devices
    for (int i = 0; i < MAX_VIDEO_DEVICES; ++i) {
        QString devicePath = QString("/dev/video%1").arg(i);
        
        if (!QFileInfo::exists(devicePath)) {
            continue;
        }
        
        CameraInfo info;
        if (queryDeviceInfo(devicePath, info) && info.isCapture) {
            m_cameraInfoList.append(info);
            
            QString displayName = QString("%1 - %2").arg(info.devicePath, info.name);
            m_availableCameras.append(displayName);
            
            qCDebug(lcCameraDetector) << "Found camera:" << displayName;
        }
    }
    
    qCDebug(lcCameraDetector) << "Found" << m_cameraInfoList.size() << "cameras";
}

bool CameraDetector::queryDeviceInfo(const QString& devicePath, CameraInfo& info)
{
    int fd = open(devicePath.toLocal8Bit().constData(), O_RDONLY);
    if (fd < 0) {
        qCDebug(lcCameraDetector) << "Failed to open" << devicePath << ":" << strerror(errno);
        return false;
    }
    
    // Query device capabilities
    struct v4l2_capability cap;
    if (ioctl(fd, VIDIOC_QUERYCAP, &cap) < 0) {
        qCDebug(lcCameraDetector) << "Failed to query capabilities for" << devicePath;
        close(fd);
        return false;
    }
    
    // Fill basic info
    info.devicePath = devicePath;
    info.name = QString::fromUtf8(reinterpret_cast<const char*>(cap.card));
    info.driver = QString::fromUtf8(reinterpret_cast<const char*>(cap.driver));
    info.busInfo = QString::fromUtf8(reinterpret_cast<const char*>(cap.bus_info));
    info.card = info.name;
    info.isCapture = isVideoCaptureDevice(fd);
    info.deviceIndex = devicePath.right(1).toInt();
    
    if (info.isCapture) {
        // Get supported formats and resolutions
        info.supportedFormats = getPixelFormats(fd);
        info.supportedResolutions = getResolutions(fd);
    }
    
    close(fd);
    return true;
}

bool CameraDetector::isVideoCaptureDevice(int fd)
{
    struct v4l2_capability cap;
    if (ioctl(fd, VIDIOC_QUERYCAP, &cap) < 0) {
        return false;
    }
    
    // Check if device has video capture capability
    if (!(cap.capabilities & V4L2_CAP_VIDEO_CAPTURE)) {
        return false;
    }
    
    // Ensure device supports streaming (most real capture devices do)
    if (!(cap.capabilities & V4L2_CAP_STREAMING)) {
        return false;
    }
    
    // Additional check: try to enumerate at least one pixel format
    // This helps filter out control-only or metadata-only devices
    struct v4l2_fmtdesc fmtDesc;
    memset(&fmtDesc, 0, sizeof(fmtDesc));
    fmtDesc.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
    fmtDesc.index = 0;
    
    if (ioctl(fd, VIDIOC_ENUM_FMT, &fmtDesc) < 0) {
        return false; // No pixel formats available = not a real capture device
    }
    
    return true;
}

QStringList CameraDetector::getPixelFormats(int fd)
{
    QStringList formats;
    struct v4l2_fmtdesc fmtDesc;
    memset(&fmtDesc, 0, sizeof(fmtDesc));
    
    fmtDesc.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
    fmtDesc.index = 0;
    
    while (ioctl(fd, VIDIOC_ENUM_FMT, &fmtDesc) == 0) {
        QString formatName = QString::fromUtf8(reinterpret_cast<const char*>(fmtDesc.description));
        QString pixelFormat = formatToString(fmtDesc.pixelformat);
        formats.append(QString("%1 (%2)").arg(formatName, pixelFormat));
        fmtDesc.index++;
    }
    
    return formats;
}

QStringList CameraDetector::getResolutions(int fd)
{
    QStringList resolutions;
    struct v4l2_frmsizeenum frameSize;
    memset(&frameSize, 0, sizeof(frameSize));
    
    // Try common pixel formats
    QList<uint32_t> commonFormats = {
        V4L2_PIX_FMT_YUYV,
        V4L2_PIX_FMT_MJPEG,
        V4L2_PIX_FMT_RGB24,
        V4L2_PIX_FMT_BGR24
    };
    
    for (uint32_t pixelFormat : commonFormats) {
        frameSize.pixel_format = pixelFormat;
        frameSize.index = 0;
        
        while (ioctl(fd, VIDIOC_ENUM_FRAMESIZES, &frameSize) == 0) {
            if (frameSize.type == V4L2_FRMSIZE_TYPE_DISCRETE) {
                QString resolution = QString("%1x%2")
                    .arg(frameSize.discrete.width)
                    .arg(frameSize.discrete.height);
                
                if (!resolutions.contains(resolution)) {
                    resolutions.append(resolution);
                }
            }
            frameSize.index++;
        }
    }
    
    return resolutions;
}

QString CameraDetector::formatToString(uint32_t format)
{
    return QString("%1%2%3%4")
        .arg(static_cast<char>(format & 0xFF))
        .arg(static_cast<char>((format >> 8) & 0xFF))
        .arg(static_cast<char>((format >> 16) & 0xFF))
        .arg(static_cast<char>((format >> 24) & 0xFF));
}

QString CameraDetector::getCameraDescription(const QString& devicePath) const
{
    for (const auto& info : m_cameraInfoList) {
        if (info.devicePath == devicePath) {
            return QString("%1 - %2").arg(info.name, info.driver);
        }
    }
    return devicePath;
}

QStringList CameraDetector::getSupportedResolutions(const QString& devicePath) const
{
    for (const auto& info : m_cameraInfoList) {
        if (info.devicePath == devicePath) {
            return info.supportedResolutions;
        }
    }
    return QStringList();
}

bool CameraDetector::isCameraAvailable(const QString& devicePath) const
{
    for (const auto& info : m_cameraInfoList) {
        if (info.devicePath == devicePath) {
            return QFileInfo::exists(devicePath);
        }
    }
    return false;
}

CameraInfo CameraDetector::getCameraInfo(const QString& devicePath) const
{
    for (const auto& info : m_cameraInfoList) {
        if (info.devicePath == devicePath) {
            return info;
        }
    }
    return CameraInfo{};
}

void CameraDetector::startAutoRefresh(int intervalMs)
{
    m_refreshTimer->start(intervalMs);
    qCDebug(lcCameraDetector) << "Started auto-refresh with interval:" << intervalMs << "ms";
}

void CameraDetector::stopAutoRefresh()
{
    m_refreshTimer->stop();
    qCDebug(lcCameraDetector) << "Stopped auto-refresh";
}

void CameraDetector::onDeviceChanged()
{
    // Debounce device changes with a short delay
    QTimer::singleShot(500, this, &CameraDetector::refreshCameras);
}

void CameraDetector::periodicRefresh()
{
    refreshCameras();
}