namespace MauiApp1;

public partial class MainPage : ContentPage
{
    private int _count;

    public MainPage() => InitializeComponent();

    private void OnClicked(object? sender, EventArgs e) => CounterLabel.Text = $"Clicked {++_count} times";
}
