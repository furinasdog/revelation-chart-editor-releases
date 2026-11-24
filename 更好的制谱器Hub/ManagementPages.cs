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
    private void MaximizeClick(object sender,RoutedEventArgs e)
    {
        if (WindowState==WindowState.Maximized) SystemCommands.RestoreWindow(this); else SystemCommands.MaximizeWindow(this);
    }
    private void CloseClick(object sender,RoutedEventArgs e) => Close();
    private void CancelJob(object sender,RoutedEventArgs e) => download?.Cancel();
    private void Navigate(string dest,bool reload=false)
    {
        bool changed=dest!=page;
        if (!changed && !reload) return;
        var pages=Navigation.Children.OfType<Button>().ToList();
        string group=(string)pages.Single(b=>Equals(b.Content,dest)).Tag;
        lastPage[group]=dest;
        foreach (var b in Groups.Children.OfType<Button>()) Selector.SetIsSelected(b,Equals(b.Content,group));
        foreach (var b in pages)
        {
            b.Visibility=Equals(b.Tag,group)?Visibility.Visible:Visibility.Collapsed;
            Selector.SetIsSelected(b,Equals(b.Content,dest));
        }
        page=dest;
        onlyInstalled=dest=="已安装";
        LibraryBody.Visibility=CatalogStatus.Visibility=OnLibrary?Visibility.Visible:Visibility.Collapsed;
        ManagerBody.Visibility=OnLibrary?Visibility.Collapsed:Visibility.Visible;
        RefreshButton.Content=OnLibrary?"刷新版本":"刷新";
        PageTitle.Text=page;EmptyState.Text="";
        if(download==null) JobStatus.Text="";
        section=null;modelCounts.Clear();Manager.Children.Clear();
        if(changed) ManagerBody.ScrollToHome();
        try
        {
            if(OnLibrary){Render();ShowNotices();if(changed) LibraryBody.ScrollToHome();}
            else switch(dest)
            {
                case "模型管理": ModelPage();break;
                case "编辑器配置": ConfigPage();break;
                case "参考工程": ReferencePage();break;
                case "使用文档": GuidePage();break;
                case "Hub 设置": SettingsPage();break;
            }
        }
        catch(Exception ex) { Message(ex.Message); }
        if(changed && AnimateControls)
        {
            var view=OnLibrary?LibraryBody:ManagerBody;
            var t=new TranslateTransform();view.RenderTransform=t;
            t.BeginAnimation(TranslateTransform.YProperty,new DoubleAnimation(5,0,TimeSpan.FromMilliseconds(140))
                {EasingFunction=new CubicEase{EasingMode=EasingMode.EaseOut},FillBehavior=FillBehavior.Stop});
        }
    }
    private void Message(string text) {JobStatus.Text=text;if(download==null) JobProgress.Visibility=JobCancel.Visibility=Visibility.Collapsed;}
    private static Button ActionButton(string name,Action action)
    {
        var b=new Button{Content=name,Margin=new Thickness(0,3,6,3),Padding=new Thickness(12,6,12,6)};
        b.Click+=(_,_)=>action();return b;
    }
    private void Act(Action work) {try{work();}catch(Exception ex){Message(ex.Message);}}
    private bool Confirm(string text) => MessageBox.Show(this,text,"更好的制谱器 Hub",MessageBoxButton.YesNo,MessageBoxImage.Question,MessageBoxResult.No)==MessageBoxResult.Yes;
    private static void OpenPath(string path) => Process.Start(new ProcessStartInfo(path){UseShellExecute=true});
    private void Heading(string text)
    {
        section=new StackPanel();
        Manager.Children.Add(new Border{Style=(Style)FindResource("Card"),Child=section});
        var label=Label(text,16,"#273344");label.FontWeight=FontWeights.SemiBold;label.Margin=new Thickness(0,0,0,7);section.Children.Add(label);
    }
    private TextBlock Detail(string text) {var label=Label(text,13,"#526477");(section??Manager).Children.Add(label);return label;}
    private WrapPanel Actions(Panel panel){var row=new WrapPanel{Margin=new Thickness(0,5,0,0)};(panel==Manager?section??Manager:panel).Children.Add(row);return row;}
    private void AddMaintenanceButtons(StackPanel panel,Release r,Release latest)
    {
        var row=Actions(panel);
        if(latest!=null) row.Children.Add(ActionButton("更新到 v"+latest.version,()=>_ = ChangeVersion(r,latest)));
        row.Children.Add(ActionButton("校验文件",()=>_ = RunJob(async (p,ct)=>{
            var bad=await library.Verify(r,p,ct);
            return bad.Count==0?"v"+r.version+" 的发行文件完整。":$"发现 {bad.Count} 个缺失或损坏文件：{string.Join("、",bad.Take(4).Select(Path.GetFileName))}。可点击「修复」。";
        })));
        if(r.size>0) row.Children.Add(ActionButton("修复",()=>_ = ChangeVersion(r,r)));
        row.Children.Add(ActionButton("删除版本",()=> {
            if(download!=null || !Confirm($"将 v{r.version} 的安装目录（含放入该目录的文件）移到回收站？"))return;
            _=RunJob(async (_,ct)=>{await Task.Run(()=>library.RemoveVersion(r.version),ct);return "版本已移到回收站。";},Render);
        }));
    }
    private Task ChangeVersion(Release from,Release to) => RunJob(async(p,ct)=>{
        await Task.Run(()=>library.Update(from,to,p,ct,options.Incremental),ct);
        return from.version==to.version?"已修复 v"+to.version+"。":$"已在原安装位置更新到 v{to.version}。";
    },Render);
    private async Task RunJob(Func<IProgress<Transfer>,CancellationToken,Task<string>> work,Action changed=null)
    {
        if(download!=null){MessageBox.Show(this,"请等待当前任务完成，或先取消。","更好的制谱器 Hub");return;}
        download=CancellationTokenSource.CreateLinkedTokenSource(lifetime.Token);
        var job=download;ApplyButton.IsEnabled=false;
        Transfer latest=new("处理中…");
        bool showing=false;
        void Show(Transfer t)
        {
            JobStatus.Text=t.Stage+(t.Total>0?$"  {100.0*t.Bytes/t.Total:F0}%":"");
            JobProgress.IsIndeterminate=t.Total<=0;
            if(t.Total>0) JobProgress.Value=100.0*t.Bytes/t.Total;
        }
        async Task Reveal()
        {
            await Task.Delay(250);
            if (download!=job) return;
            showing=true;JobCancel.Visibility=JobProgress.Visibility=Visibility.Visible;Show(latest);
        }
        _=Reveal();
        var progress=new Progress<Transfer>(t=>{if(download!=job)return;latest=t;if(showing)Show(t);});
        string result;
        try{result=await work(progress,job.Token);}
        catch(OperationCanceledException){result="已取消。";}
        catch(Exception ex){result=ex.Message;}
        finally{download=null;job.Dispose();ApplyButton.IsEnabled=true;}
        if(closing){Close();return;}
        try {changed?.Invoke();}catch(Exception ex){result=ex.Message;}
        Message(result);
    }
    private void ModelPage()
    {
        foreach(var (id,name) in new[]{("music2emo","Music2Emo · 情绪分析"),("madmom","madmom · 节拍与起音")})
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
        var selector=Actions(Manager);
        foreach(var (file,label) in new[]{(EditorProfile.Prefs,"偏好设置"),(EditorProfile.Agent,"Agent"),(EditorProfile.Mcp,"MCP")})
        {
            var b=ActionButton(label,()=>{if(configFile!=file){configFile=file;Navigate(page,true);}});
            Selector.SetIsSelected(b,file==configFile);selector.Children.Add(b);
        }
        Heading(configFile==EditorProfile.Prefs?"编辑器偏好":configFile==EditorProfile.Agent?"Agent 服务":"MCP 服务");
        Detail(Path.Combine(profile.Root,configFile));
        Detail("关闭编辑器后保存，下次打开编辑器时生效。");
        var doc=profile.Config(configFile);var values=new Dictionary<Setting,Func<string>>();
        foreach(var group in EditorProfile.Fields.Where(f=>f.File==configFile).GroupBy(f=>f.Section))
        {
            if(configFile==EditorProfile.Prefs) Heading(group.Key switch{"display"=>"显示","audio"=>"音频","analysis"=>"分析工具",_=>"快捷键"});
            foreach(var f in group)
            {
                string value=doc.Get(f);
                var row=new Grid{Margin=new Thickness(0,4,0,4)};
                row.ColumnDefinitions.Add(new ColumnDefinition{Width=new GridLength(136)});
                row.ColumnDefinitions.Add(new ColumnDefinition());
                var label=Label(f.Label,14,"#273344");row.Children.Add(label);
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
                Grid.SetColumn(field,1);row.Children.Add(field);section.Children.Add(row);
            }
        }
        Actions(Manager).Children.Add(ActionButton("保存配置",()=>Act(()=>{
            var changes=values.ToDictionary(v=>v.Key,v=>v.Value()).Where(kv=>kv.Value!=doc.Get(kv.Key)).ToDictionary();
            if(changes.Count>0) doc.Save(changes);
            Message(changes.Count>0?"配置已保存。":"配置未变更。");
        })));
    }
    private static CheckBox Toggle(string label,bool enabled) => new(){Content=label,IsChecked=enabled,Margin=new Thickness(0,7,0,7)};
    private void SettingsPage()
    {
        Heading("下载与更新");
        var inc=Toggle("优先使用增量包更新编辑器",options.Incremental);
        var auto=Toggle("自动检查并下载 Hub 更新",options.AutoUpdates);
        section.Children.Add(inc);section.Children.Add(auto);
        Heading("界面");
        var notices=Toggle("在版本库显示发行公告",options.Announcements);
        var motion=Toggle("启用界面缓动动画",options.Animations);
        section.Children.Add(notices);section.Children.Add(motion);
        Detail("Windows 关闭动画时，Hub 也会关闭页面过渡。");
        Actions(Manager).Children.Add(ActionButton("保存设置",()=>Act(()=>{
            var updated=new HubOptions(motion.IsChecked==true,inc.IsChecked==true,notices.IsChecked==true,auto.IsChecked==true);
            updated.Save(library.Root);options=updated;ShowNotices();_=CheckServices(false);Message("Hub 设置已保存。");
        })));
    }
    private void ReferencePage()
    {
        Heading("本地参考库");
        var actions=Actions(Manager);
        actions.Children.Add(ActionButton("导入参考谱",()=>Act(()=>{
            var dlg=new OpenFileDialog{Filter="谱面 JSON 或 ZIP|*.json;*.zip"};if(dlg.ShowDialog(this)!=true)return;
            profile.ImportReference(dlg.FileName);Navigate(page,true);Message("已导入参考谱数据。");
        })));
        actions.Children.Add(ActionButton("打开参考库目录",()=>Act(()=>{Directory.CreateDirectory(profile.References);OpenPath(profile.References);})));
        Detail("这里的本地参考工程也可在编辑器的脚本、Agent 和 MCP 参考库中使用。");
        Heading("内置乐句示例");Detail("随编辑器提供，可在编辑器中查询音符、事件与关键帧。");
        foreach(var item in profile.ListReferences())
        {
            Heading(item.Title);Detail($"{item.Difficulty}   ·   {item.Items} 条谱面数据"+(item.Media?"   ·   含素材包":""));
            var row=Actions(Manager);
            row.Children.Add(ActionButton("导出 JSON",()=>Act(()=>{var d=new SaveFileDialog{Filter="谱面 JSON|*.json",FileName=item.Id+".json"};if(d.ShowDialog(this)==true)File.Copy(profile.ReferenceFile(item.Id),d.FileName,true);})));
            row.Children.Add(ActionButton("删除",()=>Act(()=>{if(!Confirm("删除该参考工程、素材授权和参考库内的素材副本？"))return;profile.RemoveReference(item.Id);Navigate(page,true);})));
        }
    }
    private void GuidePage()
    {
        Heading("搜索文档");
        var search=new TextBox{Margin=new Thickness(0,5,0,1)};
        System.Windows.Automation.AutomationProperties.SetName(search,"搜索使用文档");
        Detail("搜索模块、菜单名称或操作");section.Children.Add(search);
        Heading("使用手册");
        var results=new StackPanel();section.Children.Add(results);
        void Filter()
        {
            results.Children.Clear();
            var terms=search.Text.Split(' ',StringSplitOptions.RemoveEmptyEntries|StringSplitOptions.TrimEntries);
            foreach(var chapter in Guide.Chapters.Where(c=>terms.All(t=>(c.Book+c.Title+c.Body).Contains(t,StringComparison.OrdinalIgnoreCase))))
            {
                var content=Label(chapter.Body,14,"#374B5C");content.Margin=new Thickness(12,6,6,12);
                var exp=new Expander{Header=chapter.Book+"   /   "+chapter.Title,Content=content,Margin=new Thickness(0,3,0,3),IsExpanded=terms.Length>0};
                results.Children.Add(exp);
            }
            if(results.Children.Count==0)results.Children.Add(Label("没有匹配章节。可尝试「黄键」「更新」或「MCP」。",14,"#526477"));
        }
        search.TextChanged+=(_,_)=>Filter();Filter();
    }
}

internal sealed record Chapter(string Book,string Title,string Body);
internal static class Guide
{
    internal static readonly List<Chapter> Chapters=Read();
    private static List<Chapter> Read()
    {
        var chapters=new List<Chapter>();
        foreach(var (id,book) in new[]{("hub","Hub"),("editor","制谱器"),("modules","制谱器模块")})
        {
            using var stream=typeof(Guide).Assembly.GetManifestResourceStream("RevelationHub.guides."+id+".md");
            using var reader=new StreamReader(stream);string title="概览";var lines=new List<string>();
            void Add(){string body=string.Join("\n",lines).Trim();if(body.Length>0)chapters.Add(new(book,title,body));lines.Clear();}
            while(reader.ReadLine() is string line)
            {
                if(line.StartsWith("# "))continue;
                if(line.StartsWith("## ")){Add();title=line[3..];continue;}
                if(line.StartsWith("|") && line.All(c=>c is '|' or ' ' or '-' or ':'))continue;
                lines.Add(line.Trim('|').Replace(" | ","    ·    ").Replace("**","").Replace("`","").TrimEnd());
            }
            Add();
        }
        return chapters;
    }
}
