#pragma once

#include <QObject>
#include <QGeoCoordinate>
#include <QString>
#include <QMutex>
#include <QTimer>
#include <QVideoSink>
#include <QVideoFrame>
#include <QVariantList>
#include <memory>

class VesselState : public QObject {
    Q_OBJECT

    Q_PROPERTY(double pitch READ pitch NOTIFY attitudeChanged)
    Q_PROPERTY(double roll READ roll NOTIFY attitudeChanged)
    Q_PROPERTY(double yaw READ yaw NOTIFY attitudeChanged)
    Q_PROPERTY(double heading READ heading NOTIFY navigationChanged)
    Q_PROPERTY(double speed READ speed NOTIFY navigationChanged)
    Q_PROPERTY(double latitude READ latitude NOTIFY positionChanged)
    Q_PROPERTY(double longitude READ longitude NOTIFY positionChanged)
    Q_PROPERTY(QGeoCoordinate coordinate READ coordinate NOTIFY positionChanged)

    Q_PROPERTY(double depth READ depth NOTIFY depthChanged)
    Q_PROPERTY(double waterTemp READ waterTemp NOTIFY environmentChanged)
    Q_PROPERTY(bool leakDetected READ leakDetected NOTIFY safetyChanged)
    Q_PROPERTY(bool armed READ armed NOTIFY armedChanged)
    Q_PROPERTY(QString mode READ mode NOTIFY modeChanged)

    Q_PROPERTY(double batteryVoltage READ batteryVoltage NOTIFY powerChanged)
    Q_PROPERTY(double batteryCurrent READ batteryCurrent NOTIFY powerChanged)
    Q_PROPERTY(int batteryPercentage READ batteryPercentage NOTIFY powerChanged)
    Q_PROPERTY(double batteryTemp READ batteryTemp NOTIFY powerChanged)

    Q_PROPERTY(double leftThruster READ leftThruster NOTIFY propulsionChanged)
    Q_PROPERTY(double rightThruster READ rightThruster NOTIFY propulsionChanged)

    Q_PROPERTY(int latencyMs READ latencyMs NOTIFY linkChanged)
    Q_PROPERTY(int linkQuality READ linkQuality NOTIFY linkChanged)
    Q_PROPERTY(int rpm READ rpm NOTIFY engineChanged)
    Q_PROPERTY(double coolantTemp READ coolantTemp NOTIFY engineChanged)

    Q_PROPERTY(double targetHeading READ targetHeading WRITE setTargetHeading NOTIFY targetHeadingChanged)
    Q_PROPERTY(double targetSpeed READ targetSpeed WRITE setTargetSpeed NOTIFY targetSpeedChanged)
    Q_PROPERTY(QVariantList threats READ threats NOTIFY threatsChanged)

    Q_PROPERTY(double kpHeading READ kpHeading WRITE setKpHeading NOTIFY pidGainsChanged)
    Q_PROPERTY(double kiHeading READ kiHeading WRITE setKiHeading NOTIFY pidGainsChanged)
    Q_PROPERTY(double kdHeading READ kdHeading WRITE setKdHeading NOTIFY pidGainsChanged)
    Q_PROPERTY(double kpSpeed READ kpSpeed WRITE setKpSpeed NOTIFY pidGainsChanged)
    Q_PROPERTY(double kiSpeed READ kiSpeed WRITE setKiSpeed NOTIFY pidGainsChanged)
    Q_PROPERTY(double kdSpeed READ kdSpeed WRITE setKdSpeed NOTIFY pidGainsChanged)

    Q_PROPERTY(QVideoSink* videoSink READ videoSink WRITE setVideoSink NOTIFY videoSinkChanged)

public:
    static VesselState* instance();
    explicit VesselState(QObject* parent = nullptr);
    ~VesselState() override = default;

    double pitch() const;
    double roll() const;
    double yaw() const;
    double heading() const;
    double speed() const;
    double latitude() const;
    double longitude() const;
    QGeoCoordinate coordinate() const;
    double depth() const;
    double waterTemp() const;
    bool leakDetected() const;
    bool armed() const;
    QString mode() const;
    double batteryVoltage() const;
    double batteryCurrent() const;
    int batteryPercentage() const;
    double batteryTemp() const;
    double leftThruster() const;
    double rightThruster() const;
    int latencyMs() const;
    int linkQuality() const;
    int rpm() const;
    double coolantTemp() const;

    double targetHeading() const;
    double targetSpeed() const;
    QVariantList threats() const;

    double kpHeading() const;
    double kiHeading() const;
    double kdHeading() const;
    double kpSpeed() const;
    double kiSpeed() const;
    double kdSpeed() const;

    QVideoSink* videoSink() const;

public slots:
    void setVideoSink(QVideoSink* sink);
    void pushVideoFrame(const QVideoFrame& frame);

    void updateTelemetryFromWorker(double pitch, double roll, double yaw,
                                  double lat, double lon, double speed,
                                  double heading, double depth, double waterTemp,
                                  double batV, double batA, int batPct,
                                  bool leak, bool armed, const QString& mode);

    void setPitch(double pitch);
    void setRoll(double roll);
    void setYaw(double yaw);
    void setHeading(double heading);
    void setSpeed(double speed);
    void setPosition(double lat, double lon);
    void setDepth(double depth);
    void setWaterTemp(double temp);
    void setBatteryVoltage(double v);
    void setBatteryCurrent(double a);
    void setBatteryPercentage(int pct);
    void setBatteryTemp(double temp);
    void setLeakDetected(bool leak);
    void setLatencyMs(int latency);
    void setLinkQuality(int quality);
    void setRpm(int rpm);
    void setCoolantTemp(double temp);

    void setTargetHeading(double hdg);
    void setTargetSpeed(double spd);
    void setThreats(const QVariantList& threats);

    void setKpHeading(double k);
    void setKiHeading(double k);
    void setKdHeading(double k);
    void setKpSpeed(double k);
    void setKiSpeed(double k);
    void setKdSpeed(double k);
    void setPidGains(double kpHdg, double kiHdg, double kdHdg, double kpSpd, double kiSpd, double kdSpd);

    void setThrusters(double left, double right);
    void setArmed(bool armed);
    void setMode(const QString& mode);

signals:
    void attitudeChanged();
    void navigationChanged();
    void positionChanged();
    void depthChanged();
    void environmentChanged();
    void safetyChanged();
    void armedChanged(bool armed);
    void modeChanged(const QString& mode);
    void powerChanged();
    void propulsionChanged();
    void linkChanged();
    void engineChanged();
    void targetHeadingChanged();
    void targetSpeedChanged();
    void threatsChanged();
    void pidGainsChanged();
    void videoSinkChanged();

private slots:
    void syncTelemetryToUi();

private:
    struct TelemetrySnapshot {
        double pitch{0.0};
        double roll{0.0};
        double yaw{0.0};
        double heading{0.0};
        double speed{0.0};
        double latitude{12.9716};
        double longitude{77.5946};
        double depth{0.0};
        double waterTemp{22.0};
        double batteryVoltage{24.8};
        double batteryCurrent{1.2};
        int batteryPercentage{96};
        double batteryTemp{28.5};
        double leftThruster{0.0};
        double rightThruster{0.0};
        int latencyMs{12};
        int linkQuality{98};
        int rpm{0};
        double coolantTemp{25.0};
        double targetHeading{0.0};
        double targetSpeed{0.0};
        QVariantList threats;
        double kpHeading{1.8};
        double kiHeading{0.05};
        double kdHeading{0.4};
        double kpSpeed{1.2};
        double kiSpeed{0.08};
        double kdSpeed{0.15};
        bool leakDetected{false};
        bool armed{false};
        QString mode{"TELEOP"};
    };

    static VesselState* s_instance;

    mutable QMutex m_dataMutex;
    TelemetrySnapshot m_workerState;
    TelemetrySnapshot m_uiState;
    bool m_isDirty{false};

    QTimer m_uiSyncTimer;
    QVideoSink* m_videoSink{nullptr};
};
