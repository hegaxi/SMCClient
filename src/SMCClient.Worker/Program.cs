using SMCClient.Sync;

// Worker de sincronización Jira -> SQL Server. Se puede ejecutar en consola o instalar como servicio de Windows:
//   sc.exe create "SMCClient Sync" binPath= "C:\SMCClient\worker\SMCClient.Worker.exe"
var builder = Host.CreateApplicationBuilder(args);
builder.Services.AddWindowsService(o => o.ServiceName = "SMCClient Sync");
builder.Services.AddSmcSync(builder.Configuration);
builder.Build().Run();
