using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using DraftAssistant.Presentation.Common;

namespace DraftAssistant.Presentation.Pages;

public partial class HeroesPage : UserControl, ITypeAnywhere
{
    public HeroesPage(HeroesViewModel vm)
    {
        InitializeComponent();
        DataContext = vm;
    }

    private HeroesViewModel Vm => (HeroesViewModel)DataContext;

    public void TypeText(string text)
    {
        Vm.TypeChar(text);
        // Дальше текст печатается уже в поле поиска.
        SearchBox.Focus();
        SearchBox.CaretIndex = SearchBox.Text.Length;
    }

    public void TypeBackspace() => Vm.Backspace();

    public void TypeEscape()
    {
        Vm.ClearSearch();
        Focus();
    }

    private void OnTileEnter(object sender, MouseEventArgs e)
    {
        if (sender is FrameworkElement { DataContext: HeroTile tile }) Vm.Hovered = tile;
    }

    private void OnRoleChecked(object sender, RoutedEventArgs e)
    {
        if (sender is FrameworkElement { DataContext: RoleFilter filter }) Vm.Role = filter;
    }
}
