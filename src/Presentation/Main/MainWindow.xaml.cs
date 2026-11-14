using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using DraftAssistant.Presentation.Common;

namespace DraftAssistant.Presentation.Main;

public partial class MainWindow : Window
{
    private readonly Dictionary<object, FrameworkElement> _pages;

    public MainWindow(MainViewModel vm, FrameworkElement heroes, FrameworkElement position, FrameworkElement overlay, FrameworkElement setup)
    {
        InitializeComponent();
        DataContext = vm;
        _pages = new()
        {
            [NavHeroes] = heroes,
            [NavPosition] = position,
            [NavOverlay] = overlay,
            [NavSetup] = setup,
        };
        NavHeroes.IsChecked = true;
        // В развёрнутом режиме окно без рамки заходит за края экрана на ширину рамки — компенсируем.
        StateChanged += (_, _) => Root.Margin = WindowState == WindowState.Maximized ? new Thickness(7) : new Thickness(0);
    }

    public event EventHandler? RestartToUpdateRequested;

    /// <summary>Печать в любом месте окна уходит в поиск текущего раздела (если он это поддерживает).</summary>
    protected override void OnPreviewTextInput(TextCompositionEventArgs e)
    {
        if (PageHost.Content is ITypeAnywhere page && Keyboard.FocusedElement is not TextBox && !string.IsNullOrEmpty(e.Text))
        {
            page.TypeText(e.Text);
            e.Handled = true;
            return;
        }
        base.OnPreviewTextInput(e);
    }

    protected override void OnPreviewKeyDown(KeyEventArgs e)
    {
        if (PageHost.Content is ITypeAnywhere page)
        {
            if (e.Key == Key.Escape) { page.TypeEscape(); e.Handled = true; return; }
            if (e.Key == Key.Back && Keyboard.FocusedElement is not TextBox) { page.TypeBackspace(); e.Handled = true; return; }
        }
        base.OnPreviewKeyDown(e);
    }

    public void ShowPage(string name)
    {
        var target = name switch
        {
            "position" => NavPosition,
            "overlay" => NavOverlay,
            "setup" => NavSetup,
            _ => NavHeroes,
        };
        target.IsChecked = true;
    }

    private void OnNav(object sender, RoutedEventArgs e)
    {
        if (_pages is not null && _pages.TryGetValue(sender, out var page)) PageHost.Content = page;
    }

    private void OnMinimize(object sender, RoutedEventArgs e) => WindowState = WindowState.Minimized;

    private void OnMaximize(object sender, RoutedEventArgs e) =>
        WindowState = WindowState == WindowState.Maximized ? WindowState.Normal : WindowState.Maximized;

    private void OnClose(object sender, RoutedEventArgs e) => Close();

    private void OnRestartToUpdate(object sender, RoutedEventArgs e) => RestartToUpdateRequested?.Invoke(this, EventArgs.Empty);
}
