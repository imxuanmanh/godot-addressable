using System;
using System.Threading;
using System.Threading.Tasks;
using Godot;

namespace GodotAddressables;

/// <summary>Main-thread C# facade for the addon's GDScript runtime.</summary>
/// <remarks>The client owns the service Node; callers own handles and instances. Prefer ShutdownAsync before removing the parent.</remarks>
public sealed class AddressablesClient : IDisposable
{
    private readonly Node _runtime;
    private bool _disposed;

    private AddressablesClient(Node runtime) => _runtime = runtime;

    /// <summary>Create a child runtime Node and configure a catalog snapshot.</summary>
    /// <param name="parent">Live scene-tree owner that outlives its acquired assets.</param>
    /// <param name="catalog">A valid schema-v1 catalog dictionary.</param>
    /// <param name="contentRoot">Local PCK directory or direct HTTPS content-directory URL.</param>
    /// <param name="useSourceAssets">Skip PCK preparation for development; catalog lookup is still required.</param>
    /// <exception cref="InvalidOperationException">Catalog validation or configuration failed.</exception>
    public static AddressablesClient Create(Node parent, Godot.Collections.Dictionary catalog,
        string contentRoot = "", bool useSourceAssets = false)
    {
        var script = GD.Load<GDScript>("res://addons/addressables/runtime/addressables.gd");
        var runtime = (Node)script.New().AsGodotObject();
        parent.AddChild(runtime);
        var issue = runtime.Call("configure", catalog, contentRoot, useSourceAssets).AsString();
        if (issue.Length != 0)
        {
            runtime.Free();
            throw new InvalidOperationException(issue);
        }
        return new AddressablesClient(runtime);
    }

    /// <summary>Acquire a separate token from an Inspector-assigned AddressableReference.</summary>
    /// <typeparam name="T">Expected Resource type, checked again by the C# result cast.</typeparam>
    public AssetHandle<T> Load<T>(Resource reference) where T : Resource
        => Acquire<T>(reference);

    /// <summary>Acquire a catalog key; strings do not bypass the catalog as URLs or file paths.</summary>
    public AssetHandle<T> Load<T>(string key) where T : Resource
        => Acquire<T>(key);

    // Script-defined types use a native Resource check followed by the C# T cast.
    private AssetHandle<T> Acquire<T>(Variant reference) where T : Resource
    {
        ObjectDisposedException.ThrowIf(_disposed, this);
        var nativeType = ClassDB.ClassExists(typeof(T).Name) ? typeof(T).Name : "Resource";
        var handle = _runtime.Call("load_asset", reference, nativeType).AsGodotObject();
        return new AssetHandle<T>(handle, _runtime.GetTree());
    }

    /// <summary>Close, await pending resource/HTTP work, then queue-free the runtime Node.</summary>
    /// <remarks>Does not dispose caller handles or instances. A second call returns immediately rather than joining the first task.</remarks>
    public async Task ShutdownAsync()
    {
        if (_disposed) return;
        _disposed = true;
        _runtime.Call("close");
        var tree = _runtime.GetTree();
        while (HasPendingWork())
            await tree.ToSignal(tree, SceneTree.SignalName.ProcessFrame);
        _runtime.QueueFree();
    }

    private bool HasPendingWork()
    {
        var state = _runtime.Call("debug_snapshot").AsGodotDictionary();
        return state["operations"].AsInt32() != 0 || state["pending_downloads"].AsInt32() != 0;
    }

    /// <summary>Close and queue-free without waiting; prefer ShutdownAsync for asynchronous cleanup.</summary>
    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;
        if (!GodotObject.IsInstanceValid(_runtime)) return;
        _runtime.Call("close");
        // Immediate removal drains remaining engine requests and can briefly block; prefer ShutdownAsync.
        _runtime.QueueFree();
    }
}

/// <summary>One acquisition token; Dispose releases only this owner.</summary>
/// <typeparam name="T">Expected Resource result type.</typeparam>
/// <remarks>Do not dispose shared Resource results to release ownership. Explicit token disposal is deterministic.</remarks>
public sealed class AssetHandle<T> : IDisposable where T : Resource
{
    private GodotObject? _handle;
    private readonly SceneTree _tree;

    internal AssetHandle(GodotObject handle, SceneTree tree)
        => (_handle, _tree) = (handle, tree);

    /// <summary>Whether loading ended or the token was disposed; not a success flag.</summary>
    public bool IsDone => _handle is null || _handle.Get("is_done").AsBool();

    /// <summary>Await frames and return T; failure or cancellation automatically disposes this token.</summary>
    /// <param name="cancellationToken">Cancels this token, not handles created by another Load call.</param>
    /// <returns>A borrowed Resource whose use is covered by this handle's ownership.</returns>
    /// <exception cref="OperationCanceledException">Cancellation was requested.</exception>
    /// <exception cref="ObjectDisposedException">The token was disposed before or during the wait.</exception>
    /// <exception cref="InvalidOperationException">Loading or the result type check failed.</exception>
    /// <remarks>Independent consumers need separate Load calls; multiple GetAsync calls on one handle share ownership.</remarks>
    public async Task<T> GetAsync(CancellationToken cancellationToken = default)
    {
        try
        {
            ObjectDisposedException.ThrowIf(_handle is null, this);
            cancellationToken.ThrowIfCancellationRequested();
            while (!IsDone)
            {
                await _tree.ToSignal(_tree, SceneTree.SignalName.ProcessFrame);
                cancellationToken.ThrowIfCancellationRequested();
            }
            var handle = _handle ?? throw new ObjectDisposedException(nameof(AssetHandle<T>));
            var value = handle.Call("get_result");
            return value.AsGodotObject() is T result
                ? result
                : throw new InvalidOperationException(handle.Get("error").AsString());
        }
        catch
        {
            Dispose();
            throw;
        }
    }

    /// <summary>Idempotently release the GDScript token without deleting packs or disk cache.</summary>
    public void Dispose()
    {
        _handle?.Call("release");
        _handle = null;
    }
}
