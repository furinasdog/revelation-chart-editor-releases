using Microsoft.Win32;
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Media;
using System.Windows.Media.Animation;

namespace RevelationHub;

public partial class MainWindow
{
    private readonly EditorProfile profile;
    private readonly EditorModels models;
    private HubOptions options;
    private string page;
    private readonly Dictionary<string,string> lastPage = new() { ["启动"]="已安装", ["下载"]="版本库", ["设置"]="编辑器配置", ["更多"]="参考工程" };
    private StackPanel section;
    private readonly Dictionary<string,TextBlock> modelCounts=new();
    private string configFile=EditorProfile.Prefs;
    private bool OnLibrary => page is "版本库" or "已安装";
    internal bool AnimateControls => options?.Animations==true && SystemParameters.ClientAreaAnimation;
    private void NavigateClick(object sender,RoutedEventArgs e) => Navigate((string)((Button)sender).Content);
    private void GroupClick(object sender,RoutedEventArgs e) => Navigate(lastPage[(string)((Button)sender).Content]);
    private void MinimizeClick(object sender,RoutedEventArgs e) => SystemCommands.MinimizeWindow(this);
    private void CloseClick(object sender,RoutedEventArgs e) => Close();
    private void CancelJob(object sender,RoutedEventArgs e) => download?.Cancel();
    private void Navigate(string dest,bool reload=false)
    {
        bool changed=dest!=page;
        if (!changed && !reload) return;
        var pages=Navigation.Children.OfType<Button>().ToList();
        string group=(string)pages.Single(b=>Equals(b.Content,dest)).Tag;
        lastPage[group]=dest;
        bool changedGroup = !Groups.Children.OfType<Button>().Any(b => Equals(b.Content,group) && Selector.GetIsSelected(b));
        foreach (var b in Groups.Children.OfType<Button>()) SelectNavigation(b,Equals(b.Content,group));
        int railIndex = 0;
        foreach (var b in pages)
        {
            b.Visibility=Equals(b.Tag,group)?Visibility.Visible:Visibility.Collapsed;
            SelectNavigation(b,Equals(b.Content,dest));
            if (changedGroup && b.Visibility == Visibility.Visible)
            {
                int delay = railIndex * 26;
                var enter = new TranslateTransform();
                b.RenderTransform = enter;
                b.BeginAnimation(OpacityProperty,AnimateControls ? HubMotion.Tween(0,1,100,delay) : null);
                if (AnimateControls)
                    enter.BeginAnimation(TranslateTransform.XProperty,HubMotion.Tween(-22,0,300,delay,true));
                railIndex++;
            }
        }
        page=dest;
        onlyInstalled=dest=="已安装";
        LibraryBody.Visibility=OnLibrary?Visibility.Visible:Visibility.Collapsed;
        ManagerBody.Visibility=OnLibrary?Visibility.Collapsed:Visibility.Visible;
        RefreshButton.Content=OnLibrary?"刷新版本":"刷新";
        PageTitle.Text=page;EmptyState.Text="";
        section=null;modelCounts.Clear();Manager.Children.Clear();
        if(changed) ManagerBody.ScrollToHome();
        try
        {
            if(OnLibrary){Render();if(changed) LibraryBody.ScrollToHome();}
            else switch(dest)
            {
                case "模型管理": ModelPage();break;
                case "编辑器配置": ConfigPage();break;
                case "参考工程": ReferencePage();break;
                case "使用文档": GuidePage();break;
                case "Hub 设置": SettingsPage();break;
            }
        }
        catch(Exception ex) { Message(ex.Message,true); }
        if (changed)
        {
            RevealSections(OnLibrary ? Cards : Manager);
            PageTitle.BeginAnimation(OpacityProperty, AnimateControls ? HubMotion.Tween(.45,1,120) : null);
            if (OnLibrary && Cards.Children.Count == 0)
                EmptyState.BeginAnimation(OpacityProperty, AnimateControls ? HubMotion.Tween(0,1,100) : null);
        }
    }
    private static Button ActionButton(string name,Action action)
    {
        var b=new Button{Content=name,Margin=new Thickness(0,3,6,3),Padding=new Thickness(12,6,12,6)};
        b.Click+=(_,_)=>action();return b;
    }
    private void Act(Action work) {try{work();}catch(Exception ex){Message(ex.Message,true);}}
    private bool Confirm(string text) => MessageBox.Show(this,text,"更好的制谱器 Hub",MessageBoxButton.YesNo,MessageBoxImage.Question,MessageBoxResult.No)==MessageBoxResult.Yes;
    private static void OpenPath(string path) => Process.Start(new ProcessStartInfo(path){UseShellExecute=true});
    private void Heading(string text) => section = AddSection(Manager, text);
    private StackPanel AddSection(Panel parent, string text)
    {
        var body = new StackPanel();
        parent.Children.Add(new PageCard((Style)FindResource("Card"),body));
        var label=Label(text,16,"Ink");label.FontWeight=FontWeights.SemiBold;label.Margin=new Thickness(0,0,0,7);body.Children.Add(label);
        return body;
    }
    private TextBlock Detail(string text) {var label=Label(text,13,"Muted");(section??Manager).Children.Add(label);return label;}
    private WrapPanel Actions(Panel panel){var row=new WrapPanel{Margin=new Thickness(0,5,0,0)};(panel==Manager?section??Manager:panel).Children.Add(row);return row;}

}
