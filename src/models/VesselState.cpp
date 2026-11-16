#include "VesselState.h"
#include <QtMath>
#include <QDateTime>

VesselState* VesselState::s_instance = nullptr;

VesselState* VesselState::instance() {
    if (!s_instance) {
        s_instance = new VesselState();
    }
    return s_instance;
}

VesselState::VesselState(QObject* parent) : QObject(parent) {
    s_instance = this;

    connect(&m_uiSyncTimer, &QTimer::timeout, this, &VesselState::syncTelemetryToUi);
    m_uiSyncTimer.start(16);
}

double VesselState::pitch() const { return m_uiState.pitch; }
double VesselState::roll() const { return m_uiState.roll; }
double VesselState::yaw() const { return m_uiState.yaw; }
double VesselState::heading() const { return m_uiState.heading; }
double VesselState::speed() const { return m_uiState.speed; }
double VesselState::latitude() const { return m_uiState.latitude; }
double VesselState::longitude() const { return m_uiState.longitude; }
QGeoCoordinate VesselState::coordinate() const { return QGeoCoordinate(m_uiState.latitude, m_uiState.longitude); }
double VesselState::depth() const { return m_uiState.depth; }
double VesselState::waterTemp() const { return m_uiState.waterTemp; }
bool VesselState::leakDetected() const { return m_uiState.leakDetected; }
bool VesselState::armed() const { return m_uiState.armed; }
QString VesselState::mode() const { return m_uiState.mode; }
double VesselState::batteryVoltage() const { return m_uiState.batteryVoltage; }
double VesselState::batteryCurrent() const { return m_uiState.batteryCurrent; }
int VesselState::batteryPercentage() const { return m_uiState.batteryPercentage; }
double VesselState::batteryTemp() const { return m_uiState.batteryTemp; }
double VesselState::leftThruster() const { return m_uiState.leftThruster; }
double VesselState::rightThruster() const { return m_uiState.rightThruster; }
int VesselState::latencyMs() const { return m_uiState.latencyMs; }
int VesselState::linkQuality() const { return m_uiState.linkQuality; }
int VesselState::rpm() const { return m_uiState.rpm; }
double VesselState::coolantTemp() const { return m_uiState.coolantTemp; }

double VesselState::targetHeading() const { return m_uiState.targetHeading; }
double VesselState::targetSpeed() const { return m_uiState.targetSpeed; }
QVariantList VesselState::threats() const { return m_uiState.threats; }

double VesselState::kpHeading() const { return m_uiState.kpHeading; }
double VesselState::kiHeading() const { return m_uiState.kiHeading; }
double VesselState::kdHeading() const { return m_uiState.kdHeading; }
double VesselState::kpSpeed() const { return m_uiState.kpSpeed; }
double VesselState::kiSpeed() const { return m_uiState.kiSpeed; }
double VesselState::kdSpeed() const { return m_uiState.kdSpeed; }

QVideoSink* VesselState::videoSink() const { return m_videoSink; }

void VesselState::setVideoSink(QVideoSink* sink) {
    if (m_videoSink != sink) {
        m_videoSink = sink;
        emit videoSinkChanged();
    }
}

void VesselState::pushVideoFrame(const QVideoFrame& frame) {
    if (m_videoSink) {
        m_videoSink->setVideoFrame(frame);
    }
}

void VesselState::updateTelemetryFromWorker(double pitch, double roll, double yaw,
                                          double lat, double lon, double speed,
                                          double heading, double depth, double waterTemp,
                                          double batV, double batA, int batPct,
                                          bool leak, bool armed, const QString& mode) {
    QMutexLocker locker(&m_dataMutex);
    m_workerState.pitch = pitch;
    m_workerState.roll = roll;
    m_workerState.yaw = yaw;
    m_workerState.latitude = lat;
    m_workerState.longitude = lon;
    m_workerState.speed = speed;
    m_workerState.heading = heading;
    m_workerState.depth = depth;
    m_workerState.waterTemp = waterTemp;
    m_workerState.batteryVoltage = batV;
    m_workerState.batteryCurrent = batA;
    m_workerState.batteryPercentage = batPct;
    m_workerState.leakDetected = leak;
    m_workerState.armed = armed;
    m_workerState.mode = mode;
    m_isDirty = true;
}

void VesselState::setPitch(double pitch) {
    QMutexLocker locker(&m_dataMutex);
    m_workerState.pitch = pitch;
    m_isDirty = true;
}

void VesselState::setRoll(double roll) {
    QMutexLocker locker(&m_dataMutex);
    m_workerState.roll = roll;
    m_isDirty = true;
}

void VesselState::setYaw(double yaw) {
    QMutexLocker locker(&m_dataMutex);
    m_workerState.yaw = yaw;
    m_isDirty = true;
}

void VesselState::setHeading(double heading) {
    QMutexLocker locker(&m_dataMutex);
    m_workerState.heading = heading;
    m_isDirty = true;
}

void VesselState::setSpeed(double speed) {
    QMutexLocker locker(&m_dataMutex);
    m_workerState.speed = speed;
    m_isDirty = true;
}

void VesselState::setPosition(double lat, double lon) {
    QMutexLocker locker(&m_dataMutex);
    m_workerState.latitude = lat;
    m_workerState.longitude = lon;
    m_isDirty = true;
}

void VesselState::setDepth(double depth) {
    QMutexLocker locker(&m_dataMutex);
    m_workerState.depth = depth;
    m_isDirty = true;
}

void VesselState::setWaterTemp(double temp) {
    QMutexLocker locker(&m_dataMutex);
    m_workerState.waterTemp = temp;
    m_isDirty = true;
}

void VesselState::setBatteryVoltage(double v) {
    QMutexLocker locker(&m_dataMutex);
    m_workerState.batteryVoltage = v;
    m_isDirty = true;
}

void VesselState::setBatteryCurrent(double a) {
    QMutexLocker locker(&m_dataMutex);
    m_workerState.batteryCurrent = a;
    m_isDirty = true;
}

void VesselState::setBatteryPercentage(int pct) {
    QMutexLocker locker(&m_dataMutex);
    m_workerState.batteryPercentage = pct;
    m_isDirty = true;
}

void VesselState::setBatteryTemp(double temp) {
    QMutexLocker locker(&m_dataMutex);
    m_workerState.batteryTemp = temp;
    m_isDirty = true;
}

void VesselState::setLeakDetected(bool leak) {
    QMutexLocker locker(&m_dataMutex);
    m_workerState.leakDetected = leak;
    m_isDirty = true;
}

void VesselState::setLatencyMs(int latency) {
    QMutexLocker locker(&m_dataMutex);
    m_workerState.latencyMs = latency;
    m_isDirty = true;
}

void VesselState::setLinkQuality(int quality) {
    QMutexLocker locker(&m_dataMutex);
    m_workerState.linkQuality = quality;
    m_isDirty = true;
}

void VesselState::setRpm(int rpm) {
    QMutexLocker locker(&m_dataMutex);
    m_workerState.rpm = rpm;
    m_isDirty = true;
}

void VesselState::setCoolantTemp(double temp) {
    QMutexLocker locker(&m_dataMutex);
    m_workerState.coolantTemp = temp;
    m_isDirty = true;
}

void VesselState::setTargetHeading(double hdg) {
    QMutexLocker locker(&m_dataMutex);
    m_workerState.targetHeading = hdg;
    m_isDirty = true;
}

void VesselState::setTargetSpeed(double spd) {
    QMutexLocker locker(&m_dataMutex);
    m_workerState.targetSpeed = spd;
    m_isDirty = true;
}

void VesselState::setThreats(const QVariantList& threats) {
    QMutexLocker locker(&m_dataMutex);
    m_workerState.threats = threats;
    m_isDirty = true;
}

void VesselState::setKpHeading(double k) {
    QMutexLocker locker(&m_dataMutex);
    m_workerState.kpHeading = k;
    m_isDirty = true;
}

void VesselState::setKiHeading(double k) {
    QMutexLocker locker(&m_dataMutex);
    m_workerState.kiHeading = k;
    m_isDirty = true;
}

void VesselState::setKdHeading(double k) {
    QMutexLocker locker(&m_dataMutex);
    m_workerState.kdHeading = k;
    m_isDirty = true;
}

void VesselState::setKpSpeed(double k) {
    QMutexLocker locker(&m_dataMutex);
    m_workerState.kpSpeed = k;
    m_isDirty = true;
}

void VesselState::setKiSpeed(double k) {
    QMutexLocker locker(&m_dataMutex);
    m_workerState.kiSpeed = k;
    m_isDirty = true;
}

void VesselState::setKdSpeed(double k) {
    QMutexLocker locker(&m_dataMutex);
    m_workerState.kdSpeed = k;
    m_isDirty = true;
}

void VesselState::setPidGains(double kpHdg, double kiHdg, double kdHdg, double kpSpd, double kiSpd, double kdSpd) {
    QMutexLocker locker(&m_dataMutex);
    m_workerState.kpHeading = kpHdg;
    m_workerState.kiHeading = kiHdg;
    m_workerState.kdHeading = kdHdg;
    m_workerState.kpSpeed = kpSpd;
    m_workerState.kiSpeed = kiSpd;
    m_workerState.kdSpeed = kdSpd;
    m_isDirty = true;
}

void VesselState::setThrusters(double left, double right) {
    QMutexLocker locker(&m_dataMutex);
    m_workerState.leftThruster = left;
    m_workerState.rightThruster = right;
    m_isDirty = true;
}

void VesselState::setArmed(bool armed) {
    QMutexLocker locker(&m_dataMutex);
    m_workerState.armed = armed;
    m_isDirty = true;
}

void VesselState::setMode(const QString& mode) {
    QMutexLocker locker(&m_dataMutex);
    m_workerState.mode = mode;
    m_isDirty = true;
}

void VesselState::syncTelemetryToUi() {
    TelemetrySnapshot snapshot;
    bool dirty = false;
    {
        QMutexLocker locker(&m_dataMutex);
        if (m_isDirty) {
            snapshot = m_workerState;
            dirty = true;
            m_isDirty = false;
        }
    }

    if (!dirty) return;

    bool attChanged = !qFuzzyCompare(m_uiState.pitch, snapshot.pitch) ||
                      !qFuzzyCompare(m_uiState.roll, snapshot.roll) ||
                      !qFuzzyCompare(m_uiState.yaw, snapshot.yaw);

    bool navChanged = !qFuzzyCompare(m_uiState.speed, snapshot.speed) ||
                      !qFuzzyCompare(m_uiState.heading, snapshot.heading);

    bool posChanged = !qFuzzyCompare(m_uiState.latitude, snapshot.latitude) ||
                      !qFuzzyCompare(m_uiState.longitude, snapshot.longitude);

    bool depChanged = !qFuzzyCompare(m_uiState.depth, snapshot.depth);
    bool envChanged = !qFuzzyCompare(m_uiState.waterTemp, snapshot.waterTemp);
    bool safeChanged = (m_uiState.leakDetected != snapshot.leakDetected);
    bool armChanged = (m_uiState.armed != snapshot.armed);
    bool mdChanged = (m_uiState.mode != snapshot.mode);

    bool pwrChanged = !qFuzzyCompare(m_uiState.batteryVoltage, snapshot.batteryVoltage) ||
                      !qFuzzyCompare(m_uiState.batteryCurrent, snapshot.batteryCurrent) ||
                      (m_uiState.batteryPercentage != snapshot.batteryPercentage) ||
                      !qFuzzyCompare(m_uiState.batteryTemp, snapshot.batteryTemp);

    bool propChanged = !qFuzzyCompare(m_uiState.leftThruster, snapshot.leftThruster) ||
                       !qFuzzyCompare(m_uiState.rightThruster, snapshot.rightThruster);

    bool lnkChanged = (m_uiState.latencyMs != snapshot.latencyMs) ||
                      (m_uiState.linkQuality != snapshot.linkQuality);

    bool engChanged = (m_uiState.rpm != snapshot.rpm) ||
                      !qFuzzyCompare(m_uiState.coolantTemp, snapshot.coolantTemp);

    bool tgtHdgChanged = !qFuzzyCompare(m_uiState.targetHeading, snapshot.targetHeading);
    bool tgtSpdChanged = !qFuzzyCompare(m_uiState.targetSpeed, snapshot.targetSpeed);
    bool thrChanged = (m_uiState.threats != snapshot.threats);

    bool pidChanged = !qFuzzyCompare(m_uiState.kpHeading, snapshot.kpHeading) ||
                      !qFuzzyCompare(m_uiState.kiHeading, snapshot.kiHeading) ||
                      !qFuzzyCompare(m_uiState.kdHeading, snapshot.kdHeading) ||
                      !qFuzzyCompare(m_uiState.kpSpeed, snapshot.kpSpeed) ||
                      !qFuzzyCompare(m_uiState.kiSpeed, snapshot.kiSpeed) ||
                      !qFuzzyCompare(m_uiState.kdSpeed, snapshot.kdSpeed);

    m_uiState = snapshot;

    if (attChanged) emit attitudeChanged();
    if (navChanged) emit navigationChanged();
    if (posChanged) emit positionChanged();
    if (depChanged) emit depthChanged();
    if (envChanged) emit environmentChanged();
    if (safeChanged) emit safetyChanged();
    if (armChanged) emit armedChanged(m_uiState.armed);
    if (mdChanged) emit modeChanged(m_uiState.mode);
    if (pwrChanged) emit powerChanged();
    if (propChanged) emit propulsionChanged();
    if (lnkChanged) emit linkChanged();
    if (engChanged) emit engineChanged();
    if (tgtHdgChanged) emit targetHeadingChanged();
    if (tgtSpdChanged) emit targetSpeedChanged();
    if (thrChanged) emit threatsChanged();
    if (pidChanged) emit pidGainsChanged();
}
