#pragma once

#include <QObject>
#include <QUrl>
#include <QSize>
#include <QMediaPlayer>
#include <QAudioOutput>
#include <QVideoSink>
#include <QVideoFrame>

class VideoPipeline : public QObject {
    Q_OBJECT
    Q_PROPERTY(QUrl sourceUrl READ sourceUrl WRITE setSourceUrl NOTIFY sourceUrlChanged)
    Q_PROPERTY(bool isPlaying READ isPlaying NOTIFY playStateChanged)
    Q_PROPERTY(int fps READ fps NOTIFY statsChanged)
    Q_PROPERTY(int bitrateKbps READ bitrateKbps NOTIFY statsChanged)
    Q_PROPERTY(QSize resolution READ resolution NOTIFY resolutionChanged)
    Q_PROPERTY(QString pipelineString READ pipelineString WRITE setPipelineString NOTIFY pipelineChanged)

public:
    explicit VideoPipeline(QObject* parent = nullptr);
    ~VideoPipeline() override = default;

    QUrl sourceUrl() const;
    bool isPlaying() const;
    int fps() const;
    int bitrateKbps() const;
    QSize resolution() const;
    QString pipelineString() const;

public slots:
    void setSourceUrl(const QUrl& url);
    void setPipelineString(const QString& pipeline);
    void setVideoSink(QVideoSink* sink);
    void play();
    void pause();
    void stop();
    void restart();
    void setStats(int fps, int bitrateKbps, int width, int height);

signals:
    void sourceUrlChanged(const QUrl& url);
    void playStateChanged(bool playing);
    void statsChanged();
    void resolutionChanged(const QSize& res);
    void pipelineChanged(const QString& pipeline);
    void errorOccurred(const QString& error);

private:
    QUrl m_sourceUrl{"rtsp://192.168.1.100:8554/live"};
    QString m_pipelineString{"rtspsrc location=rtsp://192.168.1.100:8554/live latency=0 drop-on-latency=true ! rtph265depay ! h265parse ! avdec_h265 ! videoconvert"};
    QMediaPlayer* m_player{nullptr};
    QAudioOutput* m_audioOutput{nullptr};
    QVideoSink* m_videoSink{nullptr};
    bool m_isPlaying{false};
    int m_fps{30};
    int m_bitrateKbps{4500};
    QSize m_resolution{1920, 1080};
};
