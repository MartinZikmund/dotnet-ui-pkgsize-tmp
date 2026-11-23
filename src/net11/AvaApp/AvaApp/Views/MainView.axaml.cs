using Avalonia.Controls;
using Avalonia.Interactivity;

namespace AvaApp.Views;

public partial class MainView : UserControl
{
    private int _count;

    public MainView() => InitializeComponent();

    private void OnClick(object? sender, RoutedEventArgs e) => CounterText.Text = $"Clicked {++_count} times";
}
