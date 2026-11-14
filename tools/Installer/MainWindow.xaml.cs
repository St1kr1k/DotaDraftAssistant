using System;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Net;
using System.Net.Http;
using System.Reflection;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Input;
using Microsoft.Win32;

namespace DraftAssistant.Installer
{
    /// <summary>
    /// Установщик-загрузчик: пользователь выбирает папку → скачивается последний Setup.exe из GitHub Releases →
    /// он запускается с --installto (штатная возможность Velopack). Автообновления потом работают в этой папке.
    /// </summary>
    public partial class MainWindow : Window
    {
        private const string PackId = "DotaDraftAssistant";
        private const string DefaultRepo = "https://github.com/St1kr1k/DotaDraftAssistant";
        private const string SetupAsset = "DotaDraftAssistant-win-Setup.exe";

        private string _parentDir;

        public MainWindow()
        {
            InitializeComponent();
            _parentDir = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
            UpdatePath();
        }

        private string TargetDir => Path.Combine(_parentDir, PackId);

        private static string RepoUrl
        {
            get
            {
                var meta = Assembly.GetExecutingAssembly().GetCustomAttributes<AssemblyMetadataAttribute>()
                    .FirstOrDefault(a => a.Key == "UpdateRepoUrl");
                return string.IsNullOrWhiteSpace(meta?.Value) ? DefaultRepo : meta.Value;
            }
        }

        private void UpdatePath()
        {
            PathText.Text = TargetDir;
            PathText.ToolTip = TargetDir;

            string error = ValidateTarget(TargetDir);
            string existing = FindExistingInstall();
            InstallButton.IsEnabled = error == null;

            if (error != null)
            {
                ShowWarning(error, false);
            }
            else if (existing != null && !SamePath(existing, TargetDir))
            {
                ShowWarning($"Приложение уже установлено в {existing}. Новая установка будет отдельной копией — " +
                            "старую лучше сначала удалить через «Приложения» Windows.", true);
            }
            else if (existing != null)
            {
                ShowWarning("Приложение уже установлено в эту папку — оно будет обновлено, настройки сохранятся.", false);
            }
            else
            {
                WarningText.Visibility = Visibility.Collapsed;
                AppsLink.Visibility = Visibility.Collapsed;
            }
        }

        private void ShowWarning(string text, bool showAppsLink)
        {
            WarningText.Text = text;
            WarningText.Visibility = Visibility.Visible;
            AppsLink.Visibility = showAppsLink ? Visibility.Visible : Visibility.Collapsed;
        }

        /// <summary>Velopack ставит без прав администратора, поэтому защищённые системные папки не подходят.</summary>
        private static string ValidateTarget(string dir)
        {
            string[] protectedRoots =
            {
                Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles),
                Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86),
                Environment.GetFolderPath(Environment.SpecialFolder.Windows),
            };
            foreach (var root in protectedRoots.Where(r => !string.IsNullOrEmpty(r)))
            {
                if (dir.StartsWith(root.TrimEnd('\\') + "\\", StringComparison.OrdinalIgnoreCase))
                    return "Program Files и Windows требуют прав администратора. Выберите другую папку, например D:\\Games.";
            }
            if (Path.GetPathRoot(dir) == null || !Directory.Exists(Path.GetPathRoot(dir)))
                return "Такого диска нет.";
            return null;
        }

        /// <summary>Где приложение уже установлено (запись «Приложения» Windows или папка по умолчанию).</summary>
        private static string FindExistingInstall()
        {
            try
            {
                using (var key = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Uninstall\" + PackId))
                {
                    if (key?.GetValue("InstallLocation") is string loc && Directory.Exists(loc)) return loc;
                }
            }
            catch (Exception) { }

            var def = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), PackId);
            return File.Exists(Path.Combine(def, "Update.exe")) ? def : null;
        }

        private static bool SamePath(string a, string b) =>
            string.Equals(Path.GetFullPath(a).TrimEnd('\\'), Path.GetFullPath(b).TrimEnd('\\'), StringComparison.OrdinalIgnoreCase);

        private void OnBrowse(object sender, RoutedEventArgs e)
        {
            using (var dlg = new System.Windows.Forms.FolderBrowserDialog
            {
                Description = "Выберите папку — программа будет установлена в подпапку DotaDraftAssistant",
                SelectedPath = _parentDir,
                ShowNewFolderButton = true,
            })
            {
                if (dlg.ShowDialog() != System.Windows.Forms.DialogResult.OK) return;
                var chosen = dlg.SelectedPath;
                // Если выбрали саму папку DotaDraftAssistant — не делаем вложенную ещё одну.
                if (string.Equals(Path.GetFileName(chosen.TrimEnd('\\')), PackId, StringComparison.OrdinalIgnoreCase))
                    chosen = Path.GetDirectoryName(chosen.TrimEnd('\\')) ?? chosen;
                _parentDir = chosen;
                UpdatePath();
            }
        }

        private async void OnInstall(object sender, RoutedEventArgs e)
        {
            ChoosePanel.Visibility = Visibility.Collapsed;
            ProgressPanel.Visibility = Visibility.Visible;
            InstallButton.IsEnabled = false;
            CancelButton.IsEnabled = false;

            var setup = Path.Combine(Path.GetTempPath(), "DotaDraftAssistant-Setup.exe");
            try
            {
                StatusText.Text = "Скачивание последней версии…";
                await DownloadAsync($"{RepoUrl}/releases/latest/download/{SetupAsset}", setup);

                StatusText.Text = "Установка…";
                SetProgress(1);
                DetailText.Text = TargetDir;
                int code = await Task.Run(() =>
                {
                    using (var p = Process.Start(new ProcessStartInfo(setup, $"--installto \"{TargetDir}\"") { UseShellExecute = false }))
                    {
                        p.WaitForExit();
                        return p.ExitCode;
                    }
                });
                if (code != 0) throw new InvalidOperationException($"Установщик завершился с кодом {code}.");

                StatusText.Text = "Готово! Приложение установлено и запущено.";
                DetailText.Text = $"Папка: {TargetDir}\nЯрлык добавлен на рабочий стол и в меню «Пуск».";
                InstallButton.Content = "Закрыть";
                InstallButton.Click -= OnInstall;
                InstallButton.Click += OnClose;
                InstallButton.IsEnabled = true;
            }
            catch (Exception ex)
            {
                StatusText.Text = "Не получилось установить";
                DetailText.Text = ex.Message;
                InstallButton.Content = "Повторить";
                InstallButton.IsEnabled = true;
                CancelButton.IsEnabled = true;
                ChoosePanel.Visibility = Visibility.Visible;
            }
            finally
            {
                try { if (File.Exists(setup)) File.Delete(setup); } catch (Exception) { }
            }
        }

        private async Task DownloadAsync(string url, string path)
        {
            ServicePointManager.SecurityProtocol |= SecurityProtocolType.Tls12;
            using (var http = new HttpClient { Timeout = TimeSpan.FromMinutes(20) })
            {
                http.DefaultRequestHeaders.UserAgent.ParseAdd("DotaDraftAssistant-Installer");
                using (var response = await http.GetAsync(url, HttpCompletionOption.ResponseHeadersRead))
                {
                    response.EnsureSuccessStatusCode();
                    long? total = response.Content.Headers.ContentLength;
                    using (var input = await response.Content.ReadAsStreamAsync())
                    using (var output = File.Create(path))
                    {
                        var buffer = new byte[81920];
                        long done = 0;
                        int read;
                        while ((read = await input.ReadAsync(buffer, 0, buffer.Length)) > 0)
                        {
                            await output.WriteAsync(buffer, 0, read);
                            done += read;
                            if (total is long t && t > 0)
                            {
                                SetProgress((double)done / t);
                                DetailText.Text = $"{done / 1048576.0:0} из {t / 1048576.0:0} МБ";
                            }
                        }
                    }
                }
            }
        }

        private void SetProgress(double fraction)
        {
            var track = ((FrameworkElement)ProgressFill.Parent).ActualWidth;
            ProgressFill.Width = Math.Max(0, Math.Min(1, fraction)) * track;
        }

        private void OnOpenApps(object sender, RoutedEventArgs e)
        {
            try { Process.Start(new ProcessStartInfo("ms-settings:appsfeatures") { UseShellExecute = true }); } catch (Exception) { }
        }

        private void OnDrag(object sender, MouseButtonEventArgs e)
        {
            if (e.ButtonState == MouseButtonState.Pressed) DragMove();
        }

        private void OnClose(object sender, RoutedEventArgs e) => Close();
    }
}
