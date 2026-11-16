using System;
using System.Collections.Generic;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Shapes;
using System.Windows.Threading;

namespace TandavGCS {
    public class Waypoint {
        public double Lat { get; set; }
        public double Lon { get; set; }
        public double Speed { get; set; }
    }

    public class MainWindow : Window {
        private double pitch = 0.0;
        private double roll = 0.0;
        private double heading = 42.0;
        private double speed = 0.0;
        private double depth = 0.0;
        private double waterTemp = 23.2;
        private double batVoltage = 24.8;
        private double batCurrent = 1.2;
        private int batPct = 96;
        private double batTemp = 28.5;
        private double leftThruster = 0.0;
        private double rightThruster = 0.0;
        private double throttle = 0.0;
        private double rudder = 0.0;
        private bool armed = false;
        private bool leakDetected = false;
        private string flightMode = "TELEOP";
        private double boatLat = 12.9716;
        private double boatLon = 77.5946;
        private List<Waypoint> waypoints = new List<Waypoint>();

        private DispatcherTimer timer;
        private Button armBtn;
        private Button estopBtn;
        private ComboBox modeCombo;
        private TextBlock linkTxt;
        private TextBlock rttTxt;
        private Border leakBadge;
        private TextBlock armIndicator;
        private TextBlock speedStat;
        private TextBlock hdgStat;
        private TextBlock depthStat;
        private TextBlock batStat;
        private TextBlock latTxt;
        private TextBlock lonTxt;
        private TextBlock wpCountTxt;
        private TextBlock pitchRollTxt;
        private TextBlock portPctTxt;
        private TextBlock stbdPctTxt;
        private Rectangle portBar;
        private Rectangle stbdBar;
        private Slider throttleSlider;
        private Slider rudderSlider;
        private TextBlock throttleTxt;
        private TextBlock rudderTxt;
        private TextBlock telBat;
        private TextBlock telBatTemp;
        private TextBlock telDepth;
        private TextBlock telWaterTemp;
        private TextBlock telLeak;
        private TextBlock compassHdgTxt;

        private Canvas horizonCanvas;
        private Canvas compassCanvas;
        private Canvas mapCanvas;
        private Canvas fpvCanvas;

        private UdpClient udpServer;

        public MainWindow() {
            Title = "TANDAV CI4 — Native Maritime Ground Control Station (GCS)";
            Width = 1380;
            Height = 860;
            MinWidth = 1100;
            MinHeight = 700;
            Background = new SolidColorBrush(Color.FromRgb(5, 8, 17));
            WindowStartupLocation = WindowStartupLocation.CenterScreen;

            waypoints.Add(new Waypoint { Lat = 12.9730, Lon = 77.5960, Speed = 3.0 });
            waypoints.Add(new Waypoint { Lat = 12.9750, Lon = 77.5990, Speed = 4.5 });
            waypoints.Add(new Waypoint { Lat = 12.9710, Lon = 77.6010, Speed = 2.0 });

            BuildUI();
            StartUdpListener();

            timer = new DispatcherTimer();
            timer.Interval = TimeSpan.FromMilliseconds(50);
            timer.Tick += OnTimerTick;
            timer.Start();

            KeyDown += OnWindowKeyDown;
        }

        private void BuildUI() {
            var rootGrid = new Grid();
            rootGrid.RowDefinitions.Add(new RowDefinition { Height = new GridLength(48) });
            rootGrid.RowDefinitions.Add(new RowDefinition { Height = new GridLength(46) });
            rootGrid.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });

            var header = CreateHeader();
            Grid.SetRow(header, 0);
            rootGrid.Children.Add(header);

            var compassBar = CreateCompassBar();
            Grid.SetRow(compassBar, 1);
            rootGrid.Children.Add(compassBar);

            var mainContent = CreateMainContent();
            Grid.SetRow(mainContent, 2);
            rootGrid.Children.Add(mainContent);

            Content = rootGrid;
        }

        private UIElement CreateHeader() {
            var border = new Border {
                Background = new SolidColorBrush(Color.FromRgb(10, 16, 29)),
                BorderBrush = new SolidColorBrush(Color.FromRgb(30, 41, 59)),
                BorderThickness = new Thickness(0, 0, 0, 1),
                Padding = new Thickness(14, 0, 14, 0)
            };

            var dock = new DockPanel();

            var leftStack = new StackPanel { Orientation = Orientation.Horizontal };
            var connDot = new Ellipse { Width = 10, Height = 10, Fill = new SolidColorBrush(Color.FromRgb(16, 185, 129)), VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 0, 8, 0) };
            var titleTxt = new TextBlock { Text = "TANDAV CI4 GCS", Foreground = Brushes.White, FontWeight = FontWeights.Bold, FontSize = 14, VerticalAlignment = VerticalAlignment.Center, FontFamily = new FontFamily("Consolas") };
            var verTxt = new TextBlock { Text = " v1.0.0-NATIVE WIN32", Foreground = new SolidColorBrush(Color.FromRgb(100, 116, 139)), FontSize = 10, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(4, 0, 16, 0), FontFamily = new FontFamily("Consolas") };

            var modeLabel = new TextBlock { Text = "MODE: ", Foreground = new SolidColorBrush(Color.FromRgb(148, 163, 184)), FontSize = 11, VerticalAlignment = VerticalAlignment.Center, FontFamily = new FontFamily("Consolas") };
            modeCombo = new ComboBox { Width = 95, Height = 26, Margin = new Thickness(0, 0, 12, 0) };
            modeCombo.Items.Add("STANDBY");
            modeCombo.Items.Add("MANUAL");
            modeCombo.Items.Add("TELEOP");
            modeCombo.Items.Add("AUTO");
            modeCombo.Items.Add("LOITER");
            modeCombo.Items.Add("RTL");
            modeCombo.SelectedIndex = 2;
            modeCombo.SelectionChanged += (s, e) => { flightMode = modeCombo.SelectedItem.ToString(); };

            armBtn = new Button {
                Content = "ARM VESSEL",
                Background = new SolidColorBrush(Color.FromRgb(16, 185, 129)),
                Foreground = Brushes.White,
                FontWeight = FontWeights.Bold,
                FontSize = 11,
                Padding = new Thickness(12, 4, 12, 4),
                Height = 28,
                FontFamily = new FontFamily("Consolas")
            };
            armBtn.Click += OnArmClicked;

            leftStack.Children.Add(connDot);
            leftStack.Children.Add(titleTxt);
            leftStack.Children.Add(verTxt);
            leftStack.Children.Add(modeLabel);
            leftStack.Children.Add(modeCombo);
            leftStack.Children.Add(armBtn);
            DockPanel.SetDock(leftStack, Dock.Left);
            dock.Children.Add(leftStack);

            var rightStack = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right };
            linkTxt = new TextBlock { Text = "LINK: 99%", Foreground = new SolidColorBrush(Color.FromRgb(16, 185, 129)), FontSize = 11, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 0, 14, 0), FontFamily = new FontFamily("Consolas") };
            rttTxt = new TextBlock { Text = "RTT: 12ms", Foreground = new SolidColorBrush(Color.FromRgb(0, 240, 255)), FontSize = 11, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 0, 14, 0), FontFamily = new FontFamily("Consolas") };

            leakBadge = new Border {
                Background = new SolidColorBrush(Color.FromRgb(239, 68, 68)),
                CornerRadius = new CornerRadius(3),
                Padding = new Thickness(8, 3, 8, 3),
                Margin = new Thickness(0, 0, 14, 0),
                Visibility = Visibility.Collapsed,
                Child = new TextBlock { Text = "LEAK DETECTED", Foreground = Brushes.White, FontWeight = FontWeights.Bold, FontSize = 10, FontFamily = new FontFamily("Consolas") }
            };

            estopBtn = new Button {
                Content = "EMERGENCY STOP",
                Background = new SolidColorBrush(Color.FromRgb(185, 28, 28)),
                Foreground = Brushes.White,
                FontWeight = FontWeights.Bold,
                FontSize = 11,
                Padding = new Thickness(14, 4, 14, 4),
                Height = 28,
                BorderBrush = new SolidColorBrush(Color.FromRgb(248, 113, 113)),
                BorderThickness = new Thickness(1.5),
                FontFamily = new FontFamily("Consolas")
            };
            estopBtn.Click += OnEstopClicked;

            rightStack.Children.Add(linkTxt);
            rightStack.Children.Add(rttTxt);
            rightStack.Children.Add(leakBadge);
            rightStack.Children.Add(estopBtn);
            DockPanel.SetDock(rightStack, Dock.Right);
            dock.Children.Add(rightStack);

            border.Child = dock;
            return border;
        }

        private UIElement CreateCompassBar() {
            var border = new Border {
                Background = new SolidColorBrush(Color.FromRgb(10, 16, 29)),
                BorderBrush = new SolidColorBrush(Color.FromRgb(30, 41, 59)),
                BorderThickness = new Thickness(0, 0, 0, 1),
                ClipToBounds = true
            };

            var grid = new Grid();
            compassCanvas = new Canvas { Height = 44, HorizontalAlignment = HorizontalAlignment.Stretch };
            grid.Children.Add(compassCanvas);

            var indicator = new Rectangle { Width = 3, Height = 24, Fill = new SolidColorBrush(Color.FromRgb(245, 158, 11)), HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };
            grid.Children.Add(indicator);

            compassHdgTxt = new TextBlock {
                Text = "042°",
                Foreground = new SolidColorBrush(Color.FromRgb(0, 240, 255)),
                FontWeight = FontWeights.Bold,
                FontSize = 10,
                FontFamily = new FontFamily("Consolas"),
                HorizontalAlignment = HorizontalAlignment.Center,
                VerticalAlignment = VerticalAlignment.Bottom,
                Margin = new Thickness(0, 0, 0, 2)
            };
            grid.Children.Add(compassHdgTxt);

            border.Child = grid;
            return border;
        }

        private UIElement CreateMainContent() {
            var grid = new Grid { Margin = new Thickness(10) };
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(62, GridUnitType.Star) });
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(38, GridUnitType.Star) });

            var leftColumn = new Grid { Margin = new Thickness(0, 0, 6, 0) };
            leftColumn.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
            leftColumn.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });

            var fpvPanel = CreateFpvPanel();
            Grid.SetRow(fpvPanel, 0);
            leftColumn.Children.Add(fpvPanel);

            var mapPanel = CreateMapPanel();
            Grid.SetRow(mapPanel, 1);
            leftColumn.Children.Add(mapPanel);

            Grid.SetColumn(leftColumn, 0);
            grid.Children.Add(leftColumn);

            var rightColumn = new Grid { Margin = new Thickness(6, 0, 0, 0) };
            rightColumn.RowDefinitions.Add(new RowDefinition { Height = new GridLength(230) });
            rightColumn.RowDefinitions.Add(new RowDefinition { Height = new GridLength(150) });
            rightColumn.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });

            var horizonPropulsionGrid = CreateHorizonAndPropulsionGrid();
            Grid.SetRow(horizonPropulsionGrid, 0);
            rightColumn.Children.Add(horizonPropulsionGrid);

            var telemetryPanel = CreateTelemetryPanel();
            Grid.SetRow(telemetryPanel, 1);
            rightColumn.Children.Add(telemetryPanel);

            var controlMixerPanel = CreateMixerPanel();
            Grid.SetRow(controlMixerPanel, 2);
            rightColumn.Children.Add(controlMixerPanel);

            Grid.SetColumn(rightColumn, 1);
            grid.Children.Add(rightColumn);

            return grid;
        }

        private UIElement CreateFpvPanel() {
            var border = new Border {
                Background = new SolidColorBrush(Color.FromRgb(10, 16, 29)),
                BorderBrush = new SolidColorBrush(Color.FromRgb(30, 41, 59)),
                BorderThickness = new Thickness(1),
                CornerRadius = new CornerRadius(4),
                Margin = new Thickness(0, 0, 0, 6),
                ClipToBounds = true
            };

            var grid = new Grid();
            fpvCanvas = new Canvas();
            grid.Children.Add(fpvCanvas);

            var topTags = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(8), HorizontalAlignment = HorizontalAlignment.Left, VerticalAlignment = VerticalAlignment.Top };
            var liveTag = new Border { Background = new SolidColorBrush(Color.FromRgb(220, 38, 38)), CornerRadius = new CornerRadius(2), Padding = new Thickness(6, 2, 6, 2), Margin = new Thickness(0, 0, 6, 0), Child = new TextBlock { Text = "LIVE FPV", Foreground = Brushes.White, FontWeight = FontWeights.Bold, FontSize = 9, FontFamily = new FontFamily("Consolas") } };
            var fpsTag = new Border { Background = new SolidColorBrush(Color.FromRgb(15, 23, 42)), BorderBrush = new SolidColorBrush(Color.FromRgb(51, 65, 85)), BorderThickness = new Thickness(1), CornerRadius = new CornerRadius(2), Padding = new Thickness(6, 2, 6, 2), Margin = new Thickness(0, 0, 6, 0), Child = new TextBlock { Text = "30 FPS", Foreground = new SolidColorBrush(Color.FromRgb(16, 185, 129)), FontWeight = FontWeights.Bold, FontSize = 9, FontFamily = new FontFamily("Consolas") } };
            var bitTag = new Border { Background = new SolidColorBrush(Color.FromRgb(15, 23, 42)), BorderBrush = new SolidColorBrush(Color.FromRgb(51, 65, 85)), BorderThickness = new Thickness(1), CornerRadius = new CornerRadius(2), Padding = new Thickness(6, 2, 6, 2), Child = new TextBlock { Text = "4500 kbps (H.265)", Foreground = new SolidColorBrush(Color.FromRgb(148, 163, 184)), FontSize = 9, FontFamily = new FontFamily("Consolas") } };
            topTags.Children.Add(liveTag);
            topTags.Children.Add(fpsTag);
            topTags.Children.Add(bitTag);
            grid.Children.Add(topTags);

            armIndicator = new TextBlock {
                Text = "DISARMED",
                Foreground = new SolidColorBrush(Color.FromRgb(148, 163, 184)),
                FontWeight = FontWeights.Bold,
                FontSize = 10,
                FontFamily = new FontFamily("Consolas"),
                Margin = new Thickness(8),
                HorizontalAlignment = HorizontalAlignment.Right,
                VerticalAlignment = VerticalAlignment.Top
            };
            grid.Children.Add(armIndicator);

            var bottomBar = new Border {
                Background = new SolidColorBrush(Color.FromArgb(210, 5, 8, 17)),
                Height = 24,
                VerticalAlignment = VerticalAlignment.Bottom,
                Padding = new Thickness(12, 0, 12, 0)
            };
            var statStack = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };
            speedStat = new TextBlock { Text = "SPD: 0.0 kts    ", Foreground = new SolidColorBrush(Color.FromRgb(0, 240, 255)), FontSize = 10, FontWeight = FontWeights.Bold, FontFamily = new FontFamily("Consolas") };
            hdgStat = new TextBlock { Text = "HDG: 042°    ", Foreground = new SolidColorBrush(Color.FromRgb(0, 240, 255)), FontSize = 10, FontWeight = FontWeights.Bold, FontFamily = new FontFamily("Consolas") };
            depthStat = new TextBlock { Text = "DEPTH: 0.0 m    ", Foreground = new SolidColorBrush(Color.FromRgb(0, 240, 255)), FontSize = 10, FontWeight = FontWeights.Bold, FontFamily = new FontFamily("Consolas") };
            batStat = new TextBlock { Text = "BAT: 96% (24.8V)", Foreground = new SolidColorBrush(Color.FromRgb(16, 185, 129)), FontSize = 10, FontWeight = FontWeights.Bold, FontFamily = new FontFamily("Consolas") };
            statStack.Children.Add(speedStat);
            statStack.Children.Add(hdgStat);
            statStack.Children.Add(depthStat);
            statStack.Children.Add(batStat);
            bottomBar.Child = statStack;
            grid.Children.Add(bottomBar);

            border.Child = grid;
            return border;
        }

        private UIElement CreateMapPanel() {
            var border = new Border {
                Background = new SolidColorBrush(Color.FromRgb(10, 16, 29)),
                BorderBrush = new SolidColorBrush(Color.FromRgb(30, 41, 59)),
                BorderThickness = new Thickness(1),
                CornerRadius = new CornerRadius(4),
                Margin = new Thickness(0, 6, 0, 0),
                ClipToBounds = true
            };

            var grid = new Grid();
            mapCanvas = new Canvas();
            mapCanvas.MouseRightButtonDown += OnMapRightClick;
            grid.Children.Add(mapCanvas);

            var tag = new Border {
                Background = new SolidColorBrush(Color.FromArgb(220, 15, 23, 42)),
                BorderBrush = new SolidColorBrush(Color.FromRgb(51, 65, 85)),
                BorderThickness = new Thickness(1),
                CornerRadius = new CornerRadius(3),
                Padding = new Thickness(8, 4, 8, 4),
                Margin = new Thickness(8),
                HorizontalAlignment = HorizontalAlignment.Left,
                VerticalAlignment = VerticalAlignment.Top
            };
            var tagStack = new StackPanel();
            latTxt = new TextBlock { Text = "LAT: 12.971600° N", Foreground = new SolidColorBrush(Color.FromRgb(0, 240, 255)), FontSize = 10, FontWeight = FontWeights.Bold, FontFamily = new FontFamily("Consolas") };
            lonTxt = new TextBlock { Text = "LON: 77.594600° E", Foreground = new SolidColorBrush(Color.FromRgb(0, 240, 255)), FontSize = 10, FontWeight = FontWeights.Bold, FontFamily = new FontFamily("Consolas") };
            wpCountTxt = new TextBlock { Text = "WAYPOINTS: 3 | DIST: 1.45 km", Foreground = new SolidColorBrush(Color.FromRgb(148, 163, 184)), FontSize = 9, FontFamily = new FontFamily("Consolas") };
            tagStack.Children.Add(latTxt);
            tagStack.Children.Add(lonTxt);
            tagStack.Children.Add(wpCountTxt);
            tag.Child = tagStack;
            grid.Children.Add(tag);

            var btnStack = new StackPanel { Margin = new Thickness(8), HorizontalAlignment = HorizontalAlignment.Right, VerticalAlignment = VerticalAlignment.Top };
            var addWpBtn = new Button { Content = "+ WP", Width = 55, Height = 22, Margin = new Thickness(0, 0, 0, 4), FontSize = 9, FontFamily = new FontFamily("Consolas") };
            addWpBtn.Click += (s, e) => {
                var last = waypoints[waypoints.Count - 1];
                waypoints.Add(new Waypoint { Lat = last.Lat + 0.002, Lon = last.Lon + 0.002, Speed = 3.5 });
                wpCountTxt.Text = "WAYPOINTS: " + waypoints.Count + " | DIST: 2.10 km";
            };
            var clrWpBtn = new Button { Content = "CLEAR", Width = 55, Height = 22, Margin = new Thickness(0, 0, 0, 4), FontSize = 9, FontFamily = new FontFamily("Consolas") };
            clrWpBtn.Click += (s, e) => {
                waypoints.Clear();
                wpCountTxt.Text = "WAYPOINTS: 0 | DIST: 0.00 km";
            };
            btnStack.Children.Add(addWpBtn);
            btnStack.Children.Add(clrWpBtn);
            grid.Children.Add(btnStack);

            var hintTxt = new TextBlock {
                Text = "RIGHT-CLICK MAP TO PLOT WAYPOINT",
                Foreground = new SolidColorBrush(Color.FromRgb(100, 116, 139)),
                FontSize = 9,
                FontFamily = new FontFamily("Consolas"),
                Margin = new Thickness(8),
                HorizontalAlignment = HorizontalAlignment.Right,
                VerticalAlignment = VerticalAlignment.Bottom
            };
            grid.Children.Add(hintTxt);

            border.Child = grid;
            return border;
        }

        private UIElement CreateHorizonAndPropulsionGrid() {
            var grid = new Grid();
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(58, GridUnitType.Star) });
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(42, GridUnitType.Star) });

            var horizonBorder = new Border {
                Background = new SolidColorBrush(Color.FromRgb(10, 16, 29)),
                BorderBrush = new SolidColorBrush(Color.FromRgb(30, 41, 59)),
                BorderThickness = new Thickness(1),
                CornerRadius = new CornerRadius(4),
                Margin = new Thickness(0, 0, 4, 6)
            };
            var hStack = new StackPanel { HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };
            var hTitle = new TextBlock { Text = "ATTITUDE HORIZON", Foreground = new SolidColorBrush(Color.FromRgb(100, 116, 139)), FontSize = 9, FontWeight = FontWeights.Bold, HorizontalAlignment = HorizontalAlignment.Center, Margin = new Thickness(0, 4, 0, 4), FontFamily = new FontFamily("Consolas") };
            horizonCanvas = new Canvas { Width = 150, Height = 150, Margin = new Thickness(0, 0, 0, 4) };
            pitchRollTxt = new TextBlock { Text = "P: 0.0° | R: 0.0°", Foreground = new SolidColorBrush(Color.FromRgb(0, 240, 255)), FontSize = 10, FontWeight = FontWeights.Bold, HorizontalAlignment = HorizontalAlignment.Center, FontFamily = new FontFamily("Consolas") };
            hStack.Children.Add(hTitle);
            hStack.Children.Add(horizonCanvas);
            hStack.Children.Add(pitchRollTxt);
            horizonBorder.Child = hStack;
            Grid.SetColumn(horizonBorder, 0);
            grid.Children.Add(horizonBorder);

            var propBorder = new Border {
                Background = new SolidColorBrush(Color.FromRgb(10, 16, 29)),
                BorderBrush = new SolidColorBrush(Color.FromRgb(30, 41, 59)),
                BorderThickness = new Thickness(1),
                CornerRadius = new CornerRadius(4),
                Margin = new Thickness(4, 0, 0, 6)
            };
            var pStack = new StackPanel { HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };
            var pTitle = new TextBlock { Text = "PROPULSION", Foreground = new SolidColorBrush(Color.FromRgb(100, 116, 139)), FontSize = 9, FontWeight = FontWeights.Bold, HorizontalAlignment = HorizontalAlignment.Center, Margin = new Thickness(0, 4, 0, 6), FontFamily = new FontFamily("Consolas") };

            var barsPanel = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Center };

            var portBox = new StackPanel { Margin = new Thickness(0, 0, 10, 0) };
            portBox.Children.Add(new TextBlock { Text = "PORT", Foreground = new SolidColorBrush(Color.FromRgb(148, 163, 184)), FontSize = 9, HorizontalAlignment = HorizontalAlignment.Center, FontFamily = new FontFamily("Consolas") });
            var pWell = new Grid { Width = 22, Height = 120, Background = new SolidColorBrush(Color.FromRgb(15, 23, 42)) };
            portBar = new Rectangle { Width = 20, Height = 0, Fill = new SolidColorBrush(Color.FromRgb(16, 185, 129)), VerticalAlignment = VerticalAlignment.Center };
            pWell.Children.Add(new Rectangle { Height = 1, Fill = new SolidColorBrush(Color.FromRgb(71, 85, 105)), VerticalAlignment = VerticalAlignment.Center });
            pWell.Children.Add(portBar);
            portBox.Children.Add(pWell);
            portPctTxt = new TextBlock { Text = "0%", Foreground = new SolidColorBrush(Color.FromRgb(16, 185, 129)), FontSize = 9, FontWeight = FontWeights.Bold, HorizontalAlignment = HorizontalAlignment.Center, Margin = new Thickness(0, 2, 0, 0), FontFamily = new FontFamily("Consolas") };
            portBox.Children.Add(portPctTxt);

            var stbdBox = new StackPanel { Margin = new Thickness(10, 0, 0, 0) };
            stbdBox.Children.Add(new TextBlock { Text = "STBD", Foreground = new SolidColorBrush(Color.FromRgb(148, 163, 184)), FontSize = 9, HorizontalAlignment = HorizontalAlignment.Center, FontFamily = new FontFamily("Consolas") });
            var sWell = new Grid { Width = 22, Height = 120, Background = new SolidColorBrush(Color.FromRgb(15, 23, 42)) };
            stbdBar = new Rectangle { Width = 20, Height = 0, Fill = new SolidColorBrush(Color.FromRgb(16, 185, 129)), VerticalAlignment = VerticalAlignment.Center };
            sWell.Children.Add(new Rectangle { Height = 1, Fill = new SolidColorBrush(Color.FromRgb(71, 85, 105)), VerticalAlignment = VerticalAlignment.Center });
            sWell.Children.Add(stbdBar);
            stbdBox.Children.Add(sWell);
            stbdPctTxt = new TextBlock { Text = "0%", Foreground = new SolidColorBrush(Color.FromRgb(16, 185, 129)), FontSize = 9, FontWeight = FontWeights.Bold, HorizontalAlignment = HorizontalAlignment.Center, Margin = new Thickness(0, 2, 0, 0), FontFamily = new FontFamily("Consolas") };
            stbdBox.Children.Add(stbdPctTxt);

            barsPanel.Children.Add(portBox);
            barsPanel.Children.Add(stbdBox);
            pStack.Children.Add(pTitle);
            pStack.Children.Add(barsPanel);
            propBorder.Child = pStack;

            Grid.SetColumn(propBorder, 1);
            grid.Children.Add(propBorder);

            return grid;
        }

        private UIElement CreateTelemetryPanel() {
            var border = new Border {
                Background = new SolidColorBrush(Color.FromRgb(10, 16, 29)),
                BorderBrush = new SolidColorBrush(Color.FromRgb(30, 41, 59)),
                BorderThickness = new Thickness(1),
                CornerRadius = new CornerRadius(4),
                Margin = new Thickness(0, 6, 0, 6),
                Padding = new Thickness(10)
            };

            var stack = new StackPanel();
            var title = new TextBlock { Text = "SYSTEM SENSORS (UW-SUITE)", Foreground = new SolidColorBrush(Color.FromRgb(100, 116, 139)), FontSize = 9, FontWeight = FontWeights.Bold, Margin = new Thickness(0, 0, 0, 8), FontFamily = new FontFamily("Consolas") };
            stack.Children.Add(title);

            var grid = new Grid();
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            grid.RowDefinitions.Add(new RowDefinition());
            grid.RowDefinitions.Add(new RowDefinition());
            grid.RowDefinitions.Add(new RowDefinition());

            telBat = new TextBlock { Text = "BAT: 24.8V | 12.4A", Foreground = new SolidColorBrush(Color.FromRgb(0, 240, 255)), FontSize = 10, FontWeight = FontWeights.Bold, Margin = new Thickness(0, 2, 0, 2), FontFamily = new FontFamily("Consolas") };
            telBatTemp = new TextBlock { Text = "TEMP: 28.5 °C", Foreground = new SolidColorBrush(Color.FromRgb(16, 185, 129)), FontSize = 10, FontWeight = FontWeights.Bold, Margin = new Thickness(0, 2, 0, 2), FontFamily = new FontFamily("Consolas") };
            telDepth = new TextBlock { Text = "DEPTH: 0.00 m", Foreground = new SolidColorBrush(Color.FromRgb(0, 240, 255)), FontSize = 10, FontWeight = FontWeights.Bold, Margin = new Thickness(0, 2, 0, 2), FontFamily = new FontFamily("Consolas") };
            telWaterTemp = new TextBlock { Text = "WATER: 23.2 °C", Foreground = new SolidColorBrush(Color.FromRgb(16, 185, 129)), FontSize = 10, FontWeight = FontWeights.Bold, Margin = new Thickness(0, 2, 0, 2), FontFamily = new FontFamily("Consolas") };
            telLeak = new TextBlock { Text = "BILGE: NOMINAL", Foreground = new SolidColorBrush(Color.FromRgb(16, 185, 129)), FontSize = 10, FontWeight = FontWeights.Bold, Margin = new Thickness(0, 2, 0, 2), FontFamily = new FontFamily("Consolas") };
            var proto = new TextBlock { Text = "LINK: UDP/0x544E4456", Foreground = new SolidColorBrush(Color.FromRgb(245, 158, 11)), FontSize = 10, FontWeight = FontWeights.Bold, Margin = new Thickness(0, 2, 0, 2), FontFamily = new FontFamily("Consolas") };

            Grid.SetRow(telBat, 0); Grid.SetColumn(telBat, 0);
            Grid.SetRow(telBatTemp, 0); Grid.SetColumn(telBatTemp, 1);
            Grid.SetRow(telDepth, 1); Grid.SetColumn(telDepth, 0);
            Grid.SetRow(telWaterTemp, 1); Grid.SetColumn(telWaterTemp, 1);
            Grid.SetRow(telLeak, 2); Grid.SetColumn(telLeak, 0);
            Grid.SetRow(proto, 2); Grid.SetColumn(proto, 1);

            grid.Children.Add(telBat);
            grid.Children.Add(telBatTemp);
            grid.Children.Add(telDepth);
            grid.Children.Add(telWaterTemp);
            grid.Children.Add(telLeak);
            grid.Children.Add(proto);

            stack.Children.Add(grid);
            border.Child = stack;
            return border;
        }

        private UIElement CreateMixerPanel() {
            var border = new Border {
                Background = new SolidColorBrush(Color.FromRgb(10, 16, 29)),
                BorderBrush = new SolidColorBrush(Color.FromRgb(30, 41, 59)),
                BorderThickness = new Thickness(1),
                CornerRadius = new CornerRadius(4),
                Margin = new Thickness(0, 6, 0, 0),
                Padding = new Thickness(10)
            };

            var stack = new StackPanel();
            var top = new DockPanel();
            var title = new TextBlock { Text = "TELEOP MIXER CONTROLS", Foreground = new SolidColorBrush(Color.FromRgb(100, 116, 139)), FontSize = 9, FontWeight = FontWeights.Bold, FontFamily = new FontFamily("Consolas") };
            var hint = new TextBlock { Text = "KEYBOARD: W/S / A/D", Foreground = new SolidColorBrush(Color.FromRgb(0, 240, 255)), FontSize = 8, FontFamily = new FontFamily("Consolas"), HorizontalAlignment = HorizontalAlignment.Right };
            top.Children.Add(title);
            top.Children.Add(hint);
            stack.Children.Add(top);

            var tDock = new DockPanel { Margin = new Thickness(0, 8, 0, 2) };
            tDock.Children.Add(new TextBlock { Text = "THROTTLE", Foreground = new SolidColorBrush(Color.FromRgb(148, 163, 184)), FontSize = 9, FontFamily = new FontFamily("Consolas") });
            throttleTxt = new TextBlock { Text = "0%", Foreground = new SolidColorBrush(Color.FromRgb(0, 240, 255)), FontSize = 9, FontWeight = FontWeights.Bold, HorizontalAlignment = HorizontalAlignment.Right, FontFamily = new FontFamily("Consolas") };
            tDock.Children.Add(throttleTxt);
            stack.Children.Add(tDock);

            throttleSlider = new Slider { Minimum = -100, Maximum = 100, Value = 0, Margin = new Thickness(0, 0, 0, 6) };
            throttleSlider.ValueChanged += (s, e) => {
                throttle = throttleSlider.Value / 100.0;
                throttleTxt.Text = ((int)throttleSlider.Value) + "%";
                UpdateMixing();
            };
            stack.Children.Add(throttleSlider);

            var rDock = new DockPanel { Margin = new Thickness(0, 4, 0, 2) };
            rDock.Children.Add(new TextBlock { Text = "RUDDER (YAW)", Foreground = new SolidColorBrush(Color.FromRgb(148, 163, 184)), FontSize = 9, FontFamily = new FontFamily("Consolas") });
            rudderTxt = new TextBlock { Text = "0%", Foreground = new SolidColorBrush(Color.FromRgb(0, 240, 255)), FontSize = 9, FontWeight = FontWeights.Bold, HorizontalAlignment = HorizontalAlignment.Right, FontFamily = new FontFamily("Consolas") };
            rDock.Children.Add(rudderTxt);
            stack.Children.Add(rDock);

            rudderSlider = new Slider { Minimum = -100, Maximum = 100, Value = 0, Margin = new Thickness(0, 0, 0, 10) };
            rudderSlider.ValueChanged += (s, e) => {
                rudder = rudderSlider.Value / 100.0;
                rudderTxt.Text = ((int)rudderSlider.Value) + "%";
                UpdateMixing();
            };
            stack.Children.Add(rudderSlider);

            var btnRow = new StackPanel { Orientation = Orientation.Horizontal };
            var zeroBtn = new Button { Content = "ZERO THRUST", Width = 110, Height = 24, Margin = new Thickness(0, 0, 8, 0), FontSize = 9, FontFamily = new FontFamily("Consolas") };
            zeroBtn.Click += (s, e) => {
                throttleSlider.Value = 0;
                rudderSlider.Value = 0;
            };
            var testLeakBtn = new Button { Content = "TEST LEAK ALARM", Width = 130, Height = 24, FontSize = 9, FontFamily = new FontFamily("Consolas") };
            testLeakBtn.Click += (s, e) => {
                leakDetected = !leakDetected;
                leakBadge.Visibility = leakDetected ? Visibility.Visible : Visibility.Collapsed;
                telLeak.Text = leakDetected ? "LEAK DETECTED!" : "NOMINAL";
                telLeak.Foreground = leakDetected ? Brushes.Red : new SolidColorBrush(Color.FromRgb(16, 185, 129));
            };
            btnRow.Children.Add(zeroBtn);
            btnRow.Children.Add(testLeakBtn);
            stack.Children.Add(btnRow);

            border.Child = stack;
            return border;
        }

        private void OnArmClicked(object sender, RoutedEventArgs e) {
            armed = !armed;
            if (armed) {
                armBtn.Content = "DISARM VESSEL";
                armBtn.Background = new SolidColorBrush(Color.FromRgb(220, 38, 38));
                armIndicator.Text = "ARMED — LIVE";
                armIndicator.Foreground = new SolidColorBrush(Color.FromRgb(239, 68, 68));
            } else {
                armBtn.Content = "ARM VESSEL";
                armBtn.Background = new SolidColorBrush(Color.FromRgb(16, 185, 129));
                armIndicator.Text = "DISARMED";
                armIndicator.Foreground = new SolidColorBrush(Color.FromRgb(148, 163, 184));
            }
            UpdateMixing();
        }

        private void OnEstopClicked(object sender, RoutedEventArgs e) {
            armed = false;
            throttleSlider.Value = 0;
            rudderSlider.Value = 0;
            modeCombo.SelectedIndex = 0;
            flightMode = "STANDBY";
            armBtn.Content = "ARM VESSEL";
            armBtn.Background = new SolidColorBrush(Color.FromRgb(16, 185, 129));
            armIndicator.Text = "ESTOP ACTIVE";
            armIndicator.Foreground = Brushes.Red;
            UpdateMixing();
        }

        private void UpdateMixing() {
            double l = Math.Max(-1.0, Math.Min(1.0, throttle + rudder));
            double r = Math.Max(-1.0, Math.Min(1.0, throttle - rudder));

            leftThruster = armed ? l : 0.0;
            rightThruster = armed ? r : 0.0;

            portBar.Height = Math.Abs(leftThruster) * 60;
            portBar.Fill = leftThruster >= 0 ? new SolidColorBrush(Color.FromRgb(16, 185, 129)) : new SolidColorBrush(Color.FromRgb(239, 68, 68));
            portPctTxt.Text = (int)(leftThruster * 100) + "%";

            stbdBar.Height = Math.Abs(rightThruster) * 60;
            stbdBar.Fill = rightThruster >= 0 ? new SolidColorBrush(Color.FromRgb(16, 185, 129)) : new SolidColorBrush(Color.FromRgb(239, 68, 68));
            stbdPctTxt.Text = (int)(rightThruster * 100) + "%";

            speed = Math.Max(0.0, (leftThruster + rightThruster) * 6.5);
            speedStat.Text = "SPD: " + speed.ToString("F1") + " kts    ";
        }

        private void OnWindowKeyDown(object sender, KeyEventArgs e) {
            if (e.Key == Key.W) {
                throttleSlider.Value = Math.Min(100, throttleSlider.Value + 10);
            } else if (e.Key == Key.S) {
                throttleSlider.Value = Math.Max(-100, throttleSlider.Value - 10);
            } else if (e.Key == Key.A) {
                rudderSlider.Value = Math.Max(-100, rudderSlider.Value - 10);
            } else if (e.Key == Key.D) {
                rudderSlider.Value = Math.Min(100, rudderSlider.Value + 10);
            } else if (e.Key == Key.Space) {
                throttleSlider.Value = 0;
                rudderSlider.Value = 0;
            }
        }

        private void OnMapRightClick(object sender, MouseButtonEventArgs e) {
            var pt = e.GetPosition(mapCanvas);
            double cx = mapCanvas.ActualWidth / 2;
            double cy = mapCanvas.ActualHeight / 2;
            double dLon = (pt.X - cx) / 10000.0;
            double dLat = -(pt.Y - cy) / 10000.0;
            waypoints.Add(new Waypoint { Lat = boatLat + dLat, Lon = boatLon + dLon, Speed = 3.0 });
            wpCountTxt.Text = "WAYPOINTS: " + waypoints.Count + " | DIST: " + (waypoints.Count * 0.7).ToString("F2") + " km";
        }

        private void StartUdpListener() {
            try {
                udpServer = new UdpClient(9001);
                udpServer.BeginReceive(OnUdpData, null);
            } catch {}
        }

        private void OnUdpData(IAsyncResult ar) {
            try {
                IPEndPoint ep = new IPEndPoint(IPAddress.Any, 0);
                byte[] bytes = udpServer.EndReceive(ar, ref ep);
                udpServer.BeginReceive(OnUdpData, null);
            } catch {}
        }

        private void OnTimerTick(object sender, EventArgs e) {
            double time = DateTime.Now.TimeOfDay.TotalSeconds;
            pitch = Math.Sin(time * 1.5) * 2.5 + (speed * 0.4);
            roll = Math.Cos(time * 1.2) * 3.8;

            if (armed) {
                heading = (heading + (rightThruster - leftThruster) * 1.5 + 360) % 360;
                double rad = heading * Math.PI / 180.0;
                boatLat += Math.Cos(rad) * (speed * 0.000002);
                boatLon += Math.Sin(rad) * (speed * 0.000002);
            }

            pitchRollTxt.Text = "P: " + pitch.ToString("F1") + "° | R: " + roll.ToString("F1") + "°";
            hdgStat.Text = "HDG: " + ((int)heading).ToString("D3") + "°    ";
            compassHdgTxt.Text = ((int)heading).ToString("D3") + "°";
            latTxt.Text = "LAT: " + boatLat.ToString("F6") + "° N";
            lonTxt.Text = "LON: " + boatLon.ToString("F6") + "° E";

            RedrawHorizon();
            RedrawCompass();
            RedrawFpv();
            RedrawMap();
        }

        private void RedrawHorizon() {
            horizonCanvas.Children.Clear();
            double w = horizonCanvas.ActualWidth;
            double h = horizonCanvas.ActualHeight;
            if (w <= 0 || h <= 0) { w = 150; h = 150; }
            double cx = w / 2;
            double cy = h / 2;

            var clipRect = new RectangleGeometry(new Rect(0, 0, w, h), cx, cy);
            horizonCanvas.Clip = clipRect;

            var transformGroup = new TransformGroup();
            transformGroup.Children.Add(new TranslateTransform(0, pitch * 2.0));
            transformGroup.Children.Add(new RotateTransform(-roll, cx, cy));

            var sky = new Rectangle { Width = w * 2, Height = h * 2, Fill = new SolidColorBrush(Color.FromRgb(16, 57, 101)), RenderTransform = transformGroup };
            Canvas.SetLeft(sky, -cx);
            Canvas.SetTop(sky, -h * 2 + cy);
            horizonCanvas.Children.Add(sky);

            var sea = new Rectangle { Width = w * 2, Height = h * 2, Fill = new SolidColorBrush(Color.FromRgb(44, 30, 14)), RenderTransform = transformGroup };
            Canvas.SetLeft(sea, -cx);
            Canvas.SetTop(sea, cy);
            horizonCanvas.Children.Add(sea);

            var line = new Line { X1 = -w, Y1 = cy, X2 = w * 2, Y2 = cy, Stroke = new SolidColorBrush(Color.FromRgb(0, 240, 255)), StrokeThickness = 1.5, RenderTransform = transformGroup };
            horizonCanvas.Children.Add(line);

            var reticleL = new Line { X1 = cx - 30, Y1 = cy, X2 = cx - 8, Y2 = cy, Stroke = new SolidColorBrush(Color.FromRgb(245, 158, 11)), StrokeThickness = 2 };
            var reticleR = new Line { X1 = cx + 8, Y1 = cy, X2 = cx + 30, Y2 = cy, Stroke = new SolidColorBrush(Color.FromRgb(245, 158, 11)), StrokeThickness = 2 };
            var reticleDot = new Ellipse { Width = 6, Height = 6, Fill = new SolidColorBrush(Color.FromRgb(245, 158, 11)) };
            Canvas.SetLeft(reticleDot, cx - 3);
            Canvas.SetTop(reticleDot, cy - 3);
            horizonCanvas.Children.Add(reticleL);
            horizonCanvas.Children.Add(reticleR);
            horizonCanvas.Children.Add(reticleDot);
        }

        private void RedrawCompass() {
            compassCanvas.Children.Clear();
            double w = compassCanvas.ActualWidth;
            double h = compassCanvas.ActualHeight;
            if (w <= 0) return;

            double centerHdg = (heading % 360 + 360) % 360;
            double ppd = 4.5;
            double startDeg = centerHdg - (w / 2 / ppd);
            double endDeg = centerHdg + (w / 2 / ppd);

            for (int deg = (int)Math.Floor(startDeg); deg <= (int)Math.Ceiling(endDeg); deg++) {
                int norm = (deg % 360 + 360) % 360;
                double x = (w / 2) + (deg - centerHdg) * ppd;

                if (norm % 5 == 0) {
                    bool major = (norm % 30 == 0);
                    var tick = new Line {
                        X1 = x, Y1 = 2, X2 = x, Y2 = major ? 16 : 8,
                        Stroke = major ? new SolidColorBrush(Color.FromRgb(0, 240, 255)) : new SolidColorBrush(Color.FromRgb(100, 116, 139)),
                        StrokeThickness = major ? 1.5 : 1
                    };
                    compassCanvas.Children.Add(tick);

                    if (major) {
                        string lbl = norm.ToString();
                        if (norm == 0) lbl = "N";
                        else if (norm == 90) lbl = "E";
                        else if (norm == 180) lbl = "S";
                        else if (norm == 270) lbl = "W";

                        var txt = new TextBlock {
                            Text = lbl,
                            Foreground = (lbl == "N" || lbl == "E" || lbl == "S" || lbl == "W") ? new SolidColorBrush(Color.FromRgb(0, 240, 255)) : new SolidColorBrush(Color.FromRgb(148, 163, 184)),
                            FontSize = 9,
                            FontWeight = FontWeights.Bold,
                            FontFamily = new FontFamily("Consolas")
                        };
                        Canvas.SetLeft(txt, x - 6);
                        Canvas.SetTop(txt, 18);
                        compassCanvas.Children.Add(txt);
                    }
                }
            }
        }

        private void RedrawFpv() {
            fpvCanvas.Children.Clear();
            double w = fpvCanvas.ActualWidth;
            double h = fpvCanvas.ActualHeight;
            if (w <= 0 || h <= 0) return;
            double cx = w / 2;
            double cy = h / 2;

            var bgSky = new Rectangle { Width = w, Height = cy, Fill = new SolidColorBrush(Color.FromRgb(6, 13, 25)) };
            var bgSea = new Rectangle { Width = w, Height = cy, Fill = new SolidColorBrush(Color.FromRgb(2, 6, 14)) };
            Canvas.SetTop(bgSea, cy);
            fpvCanvas.Children.Add(bgSky);
            fpvCanvas.Children.Add(bgSea);

            var crosshairH = new Line { X1 = cx - 35, Y1 = cy, X2 = cx + 35, Y2 = cy, Stroke = new SolidColorBrush(Color.FromArgb(180, 0, 240, 255)), StrokeThickness = 1.5 };
            var crosshairV = new Line { X1 = cx, Y1 = cy - 35, X2 = cx, Y2 = cy + 35, Stroke = new SolidColorBrush(Color.FromArgb(180, 0, 240, 255)), StrokeThickness = 1.5 };
            var ring = new Ellipse { Width = 16, Height = 16, Stroke = new SolidColorBrush(Color.FromArgb(180, 0, 240, 255)), StrokeThickness = 1.5 };
            Canvas.SetLeft(ring, cx - 8);
            Canvas.SetTop(ring, cy - 8);

            fpvCanvas.Children.Add(crosshairH);
            fpvCanvas.Children.Add(crosshairV);
            fpvCanvas.Children.Add(ring);
        }

        private void RedrawMap() {
            mapCanvas.Children.Clear();
            double w = mapCanvas.ActualWidth;
            double h = mapCanvas.ActualHeight;
            if (w <= 0 || h <= 0) return;
            double cx = w / 2;
            double cy = h / 2;

            var bg = new Rectangle { Width = w, Height = h, Fill = new SolidColorBrush(Color.FromRgb(7, 11, 20)) };
            mapCanvas.Children.Add(bg);

            int[] rings = new int[] { 35, 75, 115, 155 };
            foreach (var r in rings) {
                var el = new Ellipse { Width = r * 2, Height = r * 2, Stroke = new SolidColorBrush(Color.FromRgb(30, 41, 59)), StrokeThickness = 1 };
                Canvas.SetLeft(el, cx - r);
                Canvas.SetTop(el, cy - r);
                mapCanvas.Children.Add(el);
            }

            var gH = new Line { X1 = 0, Y1 = cy, X2 = w, Y2 = cy, Stroke = new SolidColorBrush(Color.FromRgb(30, 41, 59)), StrokeThickness = 1 };
            var gV = new Line { X1 = cx, Y1 = 0, X2 = cx, Y2 = h, Stroke = new SolidColorBrush(Color.FromRgb(30, 41, 59)), StrokeThickness = 1 };
            mapCanvas.Children.Add(gH);
            mapCanvas.Children.Add(gV);

            Point prevPt = new Point(cx, cy);
            for (int i = 0; i < waypoints.Count; i++) {
                double wx = cx + (waypoints[i].Lon - boatLon) * 10000.0;
                double wy = cy - (waypoints[i].Lat - boatLat) * 10000.0;
                Point pt = new Point(wx, wy);

                var routeLine = new Line { X1 = prevPt.X, Y1 = prevPt.Y, X2 = pt.X, Y2 = pt.Y, Stroke = new SolidColorBrush(Color.FromRgb(245, 158, 11)), StrokeThickness = 1.5, StrokeDashArray = new DoubleCollection(new double[] { 3, 3 }) };
                mapCanvas.Children.Add(routeLine);
                prevPt = pt;

                var wpDot = new Ellipse { Width = 10, Height = 10, Fill = new SolidColorBrush(Color.FromRgb(245, 158, 11)) };
                Canvas.SetLeft(wpDot, wx - 5);
                Canvas.SetTop(wpDot, wy - 5);
                mapCanvas.Children.Add(wpDot);

                var wpLbl = new TextBlock { Text = "WP" + (i + 1), Foreground = Brushes.White, FontSize = 9, FontFamily = new FontFamily("Consolas") };
                Canvas.SetLeft(wpLbl, wx + 7);
                Canvas.SetTop(wpLbl, wy - 6);
                mapCanvas.Children.Add(wpLbl);
            }

            var boat = new Polygon();
            boat.Points.Add(new Point(0, -14));
            boat.Points.Add(new Point(9, 10));
            boat.Points.Add(new Point(0, 5));
            boat.Points.Add(new Point(-9, 10));
            boat.Fill = new SolidColorBrush(Color.FromRgb(0, 240, 255));
            boat.Stroke = Brushes.White;
            boat.StrokeThickness = 1.5;
            boat.RenderTransform = new RotateTransform(heading, 0, 0);
            Canvas.SetLeft(boat, cx);
            Canvas.SetTop(boat, cy);
            mapCanvas.Children.Add(boat);
        }
    }

    public static class App {
        [STAThread]
        public static void Main() {
            var app = new Application();
            app.Run(new MainWindow());
        }
    }
}

