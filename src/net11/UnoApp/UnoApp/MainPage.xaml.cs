namespace UnoApp;

public sealed partial class MainPage : Page
{
    private int _count;

    public MainPage() => InitializeComponent();

    private void OnClick(object sender, RoutedEventArgs e) => CounterText.Text = $"Clicked {++_count} times";
}
