using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;

namespace DraftAssistant.Presentation.Pages;

public partial class HeroesPage : UserControl
{
    public HeroesPage(HeroesViewModel vm)
    {
        InitializeComponent();
        DataContext = vm;
    }

    private HeroesViewModel Vm => (HeroesViewModel)DataContext;

    private void OnTileEnter(object sender, MouseEventArgs e)
    {
        if (sender is FrameworkElement { DataContext: HeroTile tile }) Vm.Hovered = tile;
    }

    private void OnRoleChecked(object sender, RoutedEventArgs e)
    {
        if (sender is FrameworkElement { DataContext: RoleFilter filter }) Vm.Role = filter;
    }
}
