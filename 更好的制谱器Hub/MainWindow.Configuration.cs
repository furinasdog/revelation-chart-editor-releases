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
    private void ModelPage()
    {
        foreach(var (id,name) in new[]{("madmom","madmom · 节拍与起音"),("music2emo","Music2Emo · 情绪分析"),("htdemucs","HTDemucs · 四声部分离")})
        {
            Heading(name);modelCounts[id]=Detail(ModelCount(id));
            Detail(models.Location(id));
            var row=Actions(Manager);
            void UpdateCount(){if(modelCounts.TryGetValue(id,out var count)) count.Text=ModelCount(id);}
            row.Children.Add(ActionButton("下载或补齐",()=>_ = RunJob(async(p,ct)=>{await models.Install(id,p,ct);return name+" 已就绪。";},UpdateCount)));
            row.Children.Add(ActionButton("校验",()=>_ = RunJob(async(_,ct)=>{var bad=await Task.Run(()=>models.Verify(id,ct),ct);return bad.Count==0?"模型文件完整。":$"{bad.Count} 个文件需要补齐：{string.Join("、",bad.Take(3))}";})));
            row.Children.Add(ActionButton("打开目录",()=>Act(()=>OpenPath(models.Location(id)))));
            row.Children.Add(ActionButton("移除模型",()=>{if(!Confirm("移除 "+name+" 的已知模型文件？"))return;_=RunJob(async(_,ct)=>{await Task.Run(()=>models.Remove(id),ct);return "已移除模型文件。";},UpdateCount);}));
        }
        Heading("随编辑器安装的模型");Detail("Beat This! 等随版本分发的模型可在「已安装 → 校验文件」中检查或修复。");
    }
    private string ModelCount(string id) => $"{models.Count(id)} / {models.Files(id).Length} 个模型及配套文件";
    private void ConfigPage()
    {
        var tabs = new TabControl { Template=(ControlTemplate)FindResource("ConfigTabs"), ItemContainerStyle=(Style)FindResource("ConfigTab") };
        System.Windows.Automation.AutomationProperties.SetName(tabs,"编辑器配置分类");
        foreach(var (file,label) in new[]{(EditorProfile.Prefs,"偏好设置"),(EditorProfile.Agent,"Agent"),(EditorProfile.Mcp,"MCP")})
        {
            var tab = new TabItem { Header=label, Tag=file };
            tabs.Items.Add(tab);
            if (file == configFile) tabs.SelectedItem = tab;
        }
        ((TabItem)tabs.SelectedItem).Content = BuildConfigForm(configFile);
        Manager.Children.Add(tabs);
        tabs.ApplyTemplate();
        var mark = (Border)tabs.Template.FindName("SelectionMark", tabs);
        Grid.SetColumn(mark, tabs.SelectedIndex);
        tabs.SelectionChanged += (_, e) =>
        {
            if (e.OriginalSource != tabs || tabs.SelectedItem is not TabItem current) return;
            int previous = Grid.GetColumn(mark), selected = tabs.SelectedIndex;
            double cellWidth = ((Grid)mark.Parent).ActualWidth / tabs.Items.Count;
            double from = (previous-selected)*cellWidth + ((mark.RenderTransform as TranslateTransform)?.X ?? 0);
            Grid.SetColumn(mark, selected);
            configFile = (string)current.Tag;
            try { current.Content ??= BuildConfigForm(configFile); }
            catch (Exception ex) { Message(ex.Message,true); return; }
            ManagerBody.ScrollToHome();
            var slide = new TranslateTransform();
            mark.RenderTransform = slide;
            if (previous == selected) return;
            RevealSections((Panel)current.Content);
            if (!AnimateControls) return;
            slide.BeginAnimation(TranslateTransform.XProperty, HubMotion.Tween(from,0,260,settle:true));
        };
    }
    private StackPanel BuildConfigForm(string file)
    {
        var form = new StackPanel();
        var fields = AddSection(form,file==EditorProfile.Prefs?"编辑器偏好":file==EditorProfile.Agent?"Agent 服务":"MCP 服务");
        fields.Children.Add(Label(Path.Combine(profile.Root,file),13,"Muted"));
        fields.Children.Add(Label("关闭编辑器后保存，下次打开编辑器时生效。",13,"Muted"));
        var doc=profile.Config(file);var values=new Dictionary<Setting,Func<string>>();
        foreach(var group in EditorProfile.Fields.Where(f=>f.File==file).GroupBy(f=>f.Section))
        {
            if(file==EditorProfile.Prefs) fields=AddSection(form,group.Key switch{"display"=>"显示","audio"=>"音频","analysis"=>"分析工具",_=>"快捷键"});
            foreach(var f in group)
            {
                if(f.Key=="music2emo_automatic" && !doc.Contains(f)) continue;
                string value=doc.Get(f);
                var row=new Grid{Margin=new Thickness(0,4,0,4)};
                row.ColumnDefinitions.Add(new ColumnDefinition{Width=new GridLength(136)});
                row.ColumnDefinitions.Add(new ColumnDefinition());
                var label=Label(f.Label,14,"Ink");row.Children.Add(label);
                Control field;
                if(f.Kind=="bool"){var chk=Toggle("启用",value=="true");chk.Margin=new Thickness(0,2,0,2);field=chk;values[f]=()=>chk.IsChecked==true?"true":"false";}
                else if(f.Kind=="secret"){var box=new PasswordBox{Password=value};field=box;values[f]=()=>box.Password;}
                else if(f.Kind.Contains('|')){
                    var choices=f.Kind.Split('|').Select(key=>new KeyValuePair<string,string>(key, key switch{"system"=>"跟随系统","dark"=>"深色","light"=>"浅色","gray"=>"工作室灰","standard"=>"标准","original"=>"原版",_=>key})).ToArray();
                    var box=new ComboBox{ItemsSource=choices,DisplayMemberPath="Value",SelectedValuePath="Key",SelectedValue=value};
                    field=box;values[f]=()=>box.SelectedValue?.ToString()??value;
                }
                else {var box=new TextBox{Text=value};field=box;values[f]=()=>box.Text;}
                System.Windows.Automation.AutomationProperties.SetName(field,f.Label);
                Grid.SetColumn(field,1);row.Children.Add(field);fields.Children.Add(row);
            }
        }
        Actions(fields).Children.Add(ActionButton("保存配置",()=>Act(()=>{
            var changes=values.ToDictionary(v=>v.Key,v=>v.Value()).Where(kv=>kv.Value!=doc.Get(kv.Key)).ToDictionary();
            if(changes.Count>0) doc.Save(changes);
            Message(changes.Count>0?"配置已保存。":"配置未变更。");
        })));
        return form;
    }
    private static CheckBox Toggle(string label,bool enabled) => new(){Content=label,IsChecked=enabled,Margin=new Thickness(0,7,0,7)};
    private void SettingsPage()
    {
        Heading("下载与更新");
        var inc=Toggle("优先使用增量包更新编辑器",options.Incremental);
        var auto=Toggle("自动检查并下载 Hub 更新",options.AutoUpdates);
        section.Children.Add(inc);section.Children.Add(auto);
        Actions(Manager).Children.Add(ActionButton("检查 Hub 更新",()=>_ = CheckServices(true,true)));
        Heading("界面");
        var notices=Toggle("显示发行公告通知",options.Announcements);
        var motion=Toggle("启用界面缓动动画",options.Animations);
        section.Children.Add(notices);section.Children.Add(motion);
        Detail("Windows 关闭动画时，Hub 也会关闭交互动效。");
        Actions(Manager).Children.Add(ActionButton("保存设置",()=>Act(()=>{
            var updated=new HubOptions(motion.IsChecked==true,inc.IsChecked==true,notices.IsChecked==true,auto.IsChecked==true);
            updated.Save(library.Root);options=updated;if(!options.Announcements)pendingDialogs.RemoveAll(d=>d.Key=="notices");_=CheckServices(false);Message("Hub 设置已保存。");
        })));
    }
}
