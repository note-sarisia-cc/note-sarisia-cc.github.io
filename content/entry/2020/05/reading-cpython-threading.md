---
title: CPython の threading を読み解く
date: 2020-06-29
slug: reading-cpython-threading
tags: [Python]
---

# 概要

Python の `threading` モジュールは、Python インタプリタのスレッド操作の高レベルな API を提供する:

[threading - Thread-based parallelism - Python 3.8.3 documentation](https://docs.python.org/ja/3/library/threading.html)

この文章では、 `threading` モジュールでのスレッド操作を行った際のインタプリタの動きを、 `CPython` の実装を追うことで確認する。

# 準備

## 対象

`Python 3.8.3` としてリリースされた `CPython` のソースコードを対象に行う:

[python/cpython](https://github.com/python/cpython/tree/v3.8.3)

Tag: `v3.8.3`

Commit SHA: `6f8c8320e9eac9bc7a7f653b43506e75916ce8e8`

## 環境

POSIX Threads がサポートされた Linux x64 上での動きを追う

## 前提知識

- `threading` ライブラリの利用法

    [threading - Thread-based parallelism - Python 3.8.3 documentation](https://docs.python.org/ja/3/library/threading.html)

- `CPython` のソースコードレイアウト

    [23. Exploring CPython's Internals - Python Developer's Guide](https://devguide.python.org/exploring/)

- CPython Binary Extension (Native Extension) について

    [Packaging binary extensions - Python Packaging User Guide](https://packaging.python.org/guides/packaging-binary-extensions/)

    [Extending and Embedding the Python Interpreter - Python 3.8.3 documentation](https://docs.python.org/ja/3/extending/index.html)

    - 少なくとも `1. C や C++ による Python の拡張` と `2. 拡張の型の定義: チュートリアル` を読む必要がある
    - その他、必要な知識は本文中に適宜記載。

## アプリケーションコード

以下の Python コードをインタプリタにて実行した場合の動きを確認する:

```python
import threading
from time import sleep

def countdown():
    count = 10
    while (count > 0):
        print(f"{threading.get_ident()}: {count}")
        count = count - 1
        sleep(1)

th1 = threading.Thread(target=countdown)
th2 = threading.Thread(target=countdown)
th1.start()
th2.start()
th1.join()
th2.join()
```

- 実行結果

    ```
    $ ./python test_thread.py
    140150431667968: 10
    140150352901888: 10
    140150431667968: 9
    140150352901888: 9
    140150431667968: 8
    140150352901888: 8
    140150431667968: 7
    140150352901888: 7
    140150431667968: 6
    140150352901888: 6
    140150431667968: 5
    140150352901888: 5
    140150431667968: 4
    140150352901888: 4
    140150431667968: 3
    140150352901888: 3
    140150431667968: 2
    140150352901888: 2
    140150431667968: 1
    140150352901888: 1
    ```

# 検証

## `threading.Thread` のインスタンス化

```python
th1 = threading.Thread(target=countdown)
th2 = threading.Thread(target=countdown)
```

`threading.Thread.__init__()` から確認する。

- `__init__()`

    ```python
    # Lib/threading.py:761
    def __init__(self, group=None, target=None, name=None,
                     args=(), kwargs=None, *, daemon=None):
            """This constructor should always be called with keyword arguments. Arguments are:

            *group* should be None; reserved for future extension when a ThreadGroup
            class is implemented.

            *target* is the callable object to be invoked by the run()
            method. Defaults to None, meaning nothing is called.

            *name* is the thread name. By default, a unique name is constructed of
            the form "Thread-N" where N is a small decimal number.

            *args* is the argument tuple for the target invocation. Defaults to ().

            *kwargs* is a dictionary of keyword arguments for the target
            invocation. Defaults to {}.

            If a subclass overrides the constructor, it must make sure to invoke
            the base class constructor (Thread.__init__()) before doing anything
            else to the thread.

            """
            assert group is None, "group argument must be None for now"
            if kwargs is None:
                kwargs = {}
            self._target = target
            self._name = str(name or _newname())
            self._args = args
            self._kwargs = kwargs
            if daemon is not None:
                self._daemonic = daemon
            else:
                self._daemonic = current_thread().daemon
            self._ident = None
            if _HAVE_THREAD_NATIVE_ID:
                self._native_id = None
            self._tstate_lock = None
            self._started = Event()
            self._is_stopped = False
            self._initialized = True
            # Copy of sys.stderr used by self._invoke_excepthook()
            self._stderr = _sys.stderr
            self._invoke_excepthook = _make_invoke_excepthook()
            # For debugging and _after_fork()
            _dangling.add(self)
    ```

引数 `target` として渡される Callable は `self._target` に格納される。

## スレッドの実行開始

```python
th1.start()
th2.start()
```

- `start()`

    ```python
    # Lib/threading.py:834
    def start(self):
            """Start the thread's activity.

            It must be called at most once per thread object. It arranges for the
            object's run() method to be invoked in a separate thread of control.

            This method will raise a RuntimeError if called more than once on the
            same thread object.

            """
            if not self._initialized:
                raise RuntimeError("thread.__init__() not called")

            if self._started.is_set():
                raise RuntimeError("threads can only be started once")
            with _active_limbo_lock:
                _limbo[self] = self
            try:
                _start_new_thread(self._bootstrap, ())
            except Exception:
                with _active_limbo_lock:
                    del _limbo[self]
                raise
            self._started.wait()
    ```

既に開始されたスレッドかどうか確認した後に、 `_start_new_thread()` によって実際にスレッドを開始する。

- `_start_new_thread`

    ```python
    # Lib/threading.py:32
    # Rename some stuff so "from threading import *" is safe
    _start_new_thread = _thread.start_new_thread
    _allocate_lock = _thread.allocate_lock
    _set_sentinel = _thread._set_sentinel
    get_ident = _thread.get_ident
    ```

`_start_new_thread` は `_thread.start_new_thread` のエイリアスであった。 `_thread` は、 CPython インタプリタの一部であり、Native Extension として C で記述されている。実体は `Modules/_threadmodule.c` にある。

### ネイティブモジュールを追う

では、ネイティブモジュール内を読む。まずは、 Python に露出している API とネイティブ (C) で記述された関数とのマッピングを確認する。先立って、モジュール定義からメソッドテーブルを確認する。

- `threadmodule`

    ```c
    // Modules/_threadmodule.c:1497
    static struct PyModuleDef threadmodule = {
        PyModuleDef_HEAD_INIT,
        "_thread",
        thread_doc,
        -1,
        thread_methods,
        NULL,
        NULL,
        NULL,
        NULL
    };
    ```

メソッドテーブルは `thread_methods` である。

- `thread_methods`

    ```c
    // Modules/_threadmodule.c:1446
    static PyMethodDef thread_methods[] = {
        {"start_new_thread",        (PyCFunction)thread_PyThread_start_new_thread,
         METH_VARARGS, start_new_doc},
        {"start_new",               (PyCFunction)thread_PyThread_start_new_thread,
         METH_VARARGS, start_new_doc},
        {"allocate_lock",           thread_PyThread_allocate_lock,
         METH_NOARGS, allocate_doc},
        {"allocate",                thread_PyThread_allocate_lock,
         METH_NOARGS, allocate_doc},
        {"exit_thread",             thread_PyThread_exit_thread,
         METH_NOARGS, exit_doc},
        {"exit",                    thread_PyThread_exit_thread,
         METH_NOARGS, exit_doc},
        {"interrupt_main",          thread_PyThread_interrupt_main,
         METH_NOARGS, interrupt_doc},
        {"get_ident",               thread_get_ident,
         METH_NOARGS, get_ident_doc},
    #ifdef PY_HAVE_THREAD_NATIVE_ID
        {"get_native_id",           thread_get_native_id,
         METH_NOARGS, get_native_id_doc},
    #endif
        {"_count",                  thread__count,
         METH_NOARGS, _count_doc},
        {"stack_size",              (PyCFunction)thread_stack_size,
         METH_VARARGS, stack_size_doc},
        {"_set_sentinel",           thread__set_sentinel,
         METH_NOARGS, _set_sentinel_doc},
        {"_excepthook",              thread_excepthook,
         METH_O, excepthook_doc},
        {NULL,                      NULL}           /* sentinel */
    };
    ```

Python 上の `_thread.start_new_thread()` の実体は `thread_PyThread_start_new_thread` である。

- `thread_PyThread_start_new_thread()`

    ```c
    // Modules/_threadmodule.c:1024
    static PyObject *
    thread_PyThread_start_new_thread(PyObject *self, PyObject *fargs)
    {
        PyObject *func, *args, *keyw = NULL;
        struct bootstate *boot;
        unsigned long ident;

        if (!PyArg_UnpackTuple(fargs, "start_new_thread", 2, 3,
                               &func, &args, &keyw))
            return NULL;
        if (!PyCallable_Check(func)) {
            PyErr_SetString(PyExc_TypeError,
                            "first arg must be callable");
            return NULL;
        }
        if (!PyTuple_Check(args)) {
            PyErr_SetString(PyExc_TypeError,
                            "2nd arg must be a tuple");
            return NULL;
        }
        if (keyw != NULL && !PyDict_Check(keyw)) {
            PyErr_SetString(PyExc_TypeError,
                            "optional 3rd arg must be a dictionary");
            return NULL;
        }
        boot = PyMem_NEW(struct bootstate, 1);
        if (boot == NULL)
            return PyErr_NoMemory();
        boot->interp = _PyInterpreterState_Get();
        boot->func = func;
        boot->args = args;
        boot->keyw = keyw;
        boot->tstate = _PyThreadState_Prealloc(boot->interp);
        if (boot->tstate == NULL) {
            PyMem_DEL(boot);
            return PyErr_NoMemory();
        }
        Py_INCREF(func);
        Py_INCREF(args);
        Py_XINCREF(keyw);
        PyEval_InitThreads(); /* Start the interpreter's thread-awareness */
        ident = PyThread_start_new_thread(t_bootstrap, (void*) boot);
        if (ident == PYTHREAD_INVALID_THREAD_ID) {
            PyErr_SetString(ThreadError, "can't start new thread");
            Py_DECREF(func);
            Py_DECREF(args);
            Py_XDECREF(keyw);
            PyThreadState_Clear(boot->tstate);
            PyMem_DEL(boot);
            return NULL;
        }
        return PyLong_FromUnsignedLong(ident);
    }

    PyDoc_STRVAR(start_new_doc,
    "start_new_thread(function, args[, kwargs])\n\
    (start_new() is an obsolete synonym)\n\
    \n\
    Start a new thread and return its identifier.  The thread will call the\n\
    function with positional arguments from the tuple args and keyword arguments\n\
    taken from the optional dictionary kwargs.  The thread exits when the\n\
    function returns; the return value is ignored.  The thread will also exit\n\
    when the function raises an unhandled exception; a stack trace will be\n\
    printed unless the exception is SystemExit.\n");
    ```

### `PyEvel_InitThreads()`

- `PyEvel_InitThreads()`

    ```c
    // Python/ceval.c:200
    void
    PyEval_InitThreads(void)
    {
        _PyRuntimeState *runtime = &_PyRuntime;
        struct _ceval_runtime_state *ceval = &runtime->ceval;
        struct _gil_runtime_state *gil = &ceval->gil;
        if (gil_created(gil)) {
            return;
        }

        PyThread_init_thread();
        create_gil(gil);
        PyThreadState *tstate = _PyRuntimeState_GetThreadState(runtime);
        take_gil(ceval, tstate);

        struct _pending_calls *pending = &ceval->pending;
        pending->lock = PyThread_allocate_lock();
        if (pending->lock == NULL) {
            Py_FatalError("Can't initialize threads for pending calls");
        }
    }
    ```

`GIL` が初期化されていなければ `create_gil()` で初期化し、続けて `take_gil()` で `GIL` を獲得する。スレッドを建てようとするときに初めて `GIL` を初期化しているため、インタプリタがシングルスレッドで走っている時は `GIL` を利用しない。

### `PyThread_start_new_thread()`

- `PyThread_start_new_thread()`

    環境によって実装が異なる。 Windows なら `Python/threda_nt.h` 、 POSIX なら `Python/thread_pthread.h` が利用される。

    ```c
    // Python/thread_pthread.h:236
    unsigned long
    PyThread_start_new_thread(void (*func)(void *), void *arg)
    {
        pthread_t th;
        int status;
    #if defined(THREAD_STACK_SIZE) || defined(PTHREAD_SYSTEM_SCHED_SUPPORTED)
        pthread_attr_t attrs;
    #endif
    #if defined(THREAD_STACK_SIZE)
        size_t      tss;
    #endif

        dprintf(("PyThread_start_new_thread called\n"));
        if (!initialized)
            PyThread_init_thread();

    #if defined(THREAD_STACK_SIZE) || defined(PTHREAD_SYSTEM_SCHED_SUPPORTED)
        if (pthread_attr_init(&attrs) != 0)
            return PYTHREAD_INVALID_THREAD_ID;
    #endif
    #if defined(THREAD_STACK_SIZE)
        PyThreadState *tstate = _PyThreadState_GET();
        size_t stacksize = tstate ? tstate->interp->pythread_stacksize : 0;
        tss = (stacksize != 0) ? stacksize : THREAD_STACK_SIZE;
        if (tss != 0) {
            if (pthread_attr_setstacksize(&attrs, tss) != 0) {
                pthread_attr_destroy(&attrs);
                return PYTHREAD_INVALID_THREAD_ID;
            }
        }
    #endif
    #if defined(PTHREAD_SYSTEM_SCHED_SUPPORTED)
        pthread_attr_setscope(&attrs, PTHREAD_SCOPE_SYSTEM);
    #endif

        pythread_callback *callback = PyMem_RawMalloc(sizeof(pythread_callback));

        if (callback == NULL) {
          return PYTHREAD_INVALID_THREAD_ID;
        }

        callback->func = func;
        callback->arg = arg;

        status = pthread_create(&th,
    #if defined(THREAD_STACK_SIZE) || defined(PTHREAD_SYSTEM_SCHED_SUPPORTED)
                                 &attrs,
    #else
                                 (pthread_attr_t*)NULL,
    #endif
                                 pythread_wrapper, callback);

    #if defined(THREAD_STACK_SIZE) || defined(PTHREAD_SYSTEM_SCHED_SUPPORTED)
        pthread_attr_destroy(&attrs);
    #endif

        if (status != 0) {
            PyMem_RawFree(callback);
            return PYTHREAD_INVALID_THREAD_ID;
        }

        pthread_detach(th);

    #if SIZEOF_PTHREAD_T <= SIZEOF_LONG
        return (unsigned long) th;
    #else
        return (unsigned long) *(unsigned long *) &th;
    #endif
    }
    ```

ようやく `pthread_create()` が登場する。 Python  のスレッドは OS のネイティブスレッドであることがわかる。

[PTHREAD_CREATE](https://linuxjm.osdn.jp/html/glibc-linuxthreads/man3/pthread_create.3.html)

`start_routine` は `pythread_wrapper` である:

- `pythread_wrapper()`

    ```c
    // Python/thread_pthread.h:223
    static void *
    pythread_wrapper(void *arg)
    {
        /* copy func and func_arg and free the temporary structure */
        pythread_callback *callback = arg;
        void (*func)(void *) = callback->func;
        void *func_arg = callback->arg;
        PyMem_RawFree(arg);

        func(func_arg);
        return NULL;
    }
    ```

引数として渡された `pythread_callback` の `callback->func` を、 `callback->arg` を引数として実行する。この `func` と `arg` は、 `PyThread_start_new_thread` へ渡された引数であり、 `func` が `t_bootstrap` 、 `arg` が `struct bootstate` 型の `boot` である。

### `t_bootstrap`

- `t_bootstrap()`

    ```c
    // Modules/_threadmodule.c:990
    static void
    t_bootstrap(void *boot_raw)
    {
        struct bootstate *boot = (struct bootstate *) boot_raw;
        PyThreadState *tstate;
        PyObject *res;

        tstate = boot->tstate;
        tstate->thread_id = PyThread_get_thread_ident();
        _PyThreadState_Init(&_PyRuntime, tstate);
        PyEval_AcquireThread(tstate);
        tstate->interp->num_threads++;
        res = PyObject_Call(boot->func, boot->args, boot->keyw);
        if (res == NULL) {
            if (PyErr_ExceptionMatches(PyExc_SystemExit))
                /* SystemExit is ignored silently */
                PyErr_Clear();
            else {
                _PyErr_WriteUnraisableMsg("in thread started by", boot->func);
            }
        }
        else {
            Py_DECREF(res);
        }
        Py_DECREF(boot->func);
        Py_DECREF(boot->args);
        Py_XDECREF(boot->keyw);
        PyMem_DEL(boot_raw);
        tstate->interp->num_threads--;
        PyThreadState_Clear(tstate);
        PyThreadState_DeleteCurrent();
        PyThread_exit_thread();
    }
    ```

`bootstate` 構造体 `boot` に詰められて渡された `boot->func` , `boot->args` , `boot->keyw` を `PyObject_Call()` に渡し、Python コードとして実行する。

[Object Protocol - Python 3.8.3 documentation](https://docs.python.org/ja/3/c-api/object.html#c.PyObject_Call)

### `boot` , `struct bootstate`

`boot` は `struct bootstate` 型の変数であり、スレッド生成後に実行される Python コードや引数が格納されている。

- `struct bootstate`

    ```c
    // Modules/_threadmodule.c:982
    struct bootstate {
        PyInterpreterState *interp;
        PyObject *func;
        PyObject *args;
        PyObject *keyw;
        PyThreadState *tstate;
    };
    ```

実際に `boot` に詰められる中身を確認する。

`threading` モジュールの `start()` から辿ると:

- `_bootstrap()` , `_bootstrap_inner()`

    ```python
    # Lib/threading.py:852
                _start_new_thread(self._bootstrap, ())
    ```

    ```python
    # Lib/threading.py:876
    def _bootstrap(self):
            # Wrapper around the real bootstrap code that ignores
            # exceptions during interpreter cleanup.  Those typically
            # happen when a daemon thread wakes up at an unfortunate
            # moment, finds the world around it destroyed, and raises some
            # random exception *** while trying to report the exception in
            # _bootstrap_inner() below ***.  Those random exceptions
            # don't help anybody, and they confuse users, so we suppress
            # them.  We suppress them only when it appears that the world
            # indeed has already been destroyed, so that exceptions in
            # _bootstrap_inner() during normal business hours are properly
            # reported.  Also, we only suppress them for daemonic threads;
            # if a non-daemonic encounters this, something else is wrong.
            try:
                self._bootstrap_inner()
            except:
                if self._daemonic and _sys is None:
                    return
                raise
    ```

    ```python
    # Lib/threading.py:915
    def _bootstrap_inner(self):
            try:
                self._set_ident()
                self._set_tstate_lock()
                if _HAVE_THREAD_NATIVE_ID:
                    self._set_native_id()
                self._started.set()
                with _active_limbo_lock:
                    _active[self._ident] = self
                    del _limbo[self]

                if _trace_hook:
                    _sys.settrace(_trace_hook)
                if _profile_hook:
                    _sys.setprofile(_profile_hook)

                try:
                    self.run()
                except:
                    self._invoke_excepthook(self)
            finally:
                with _active_limbo_lock:
                    try:
                        # We don't call self._delete() because it also
                        # grabs _active_limbo_lock.
                        del _active[get_ident()]
                    except:
                        pass
    ```

`self._bootstrap()` は `self.run()` をラップしているだけであった。

- `self.run()`

    ```python
    def run(self):
            """Method representing the thread's activity.

            You may override this method in a subclass. The standard run() method
            invokes the callable object passed to the object's constructor as the
            target argument, if any, with sequential and keyword arguments taken
            from the args and kwargs arguments, respectively.

            """
            try:
                if self._target:
                    self._target(*self._args, **self._kwargs)
            finally:
                # Avoid a refcycle if the thread is running a function with
                # an argument that has a member that points to the thread.
                del self._target, self._args, self._kwargs
    ```

`Thread.run()` はデフォルトでは `self._target()` を実行する他、オーバーライドすることもできる。

### まとめ

- CPython のスレッドは OS のネイティブスレッド。POSIX なら `pthread`
- 別スレッドの生成時に初めて GIL の初期化が行われる。インタプリタがメインスレッドのみで走っている場合は GIL は初期化されず、用いられない。

## スレッドの完了待ち合わせ

```python
th1.join()
th2.join()
```

- `join()`

    ```python
    # Lib/threading.py:979
    def join(self, timeout=None):
            """Wait until the thread terminates.

            This blocks the calling thread until the thread whose join() method is
            called terminates -- either normally or through an unhandled exception
            or until the optional timeout occurs.

            When the timeout argument is present and not None, it should be a
            floating point number specifying a timeout for the operation in seconds
            (or fractions thereof). As join() always returns None, you must call
            is_alive() after join() to decide whether a timeout happened -- if the
            thread is still alive, the join() call timed out.

            When the timeout argument is not present or None, the operation will
            block until the thread terminates.

            A thread can be join()ed many times.

            join() raises a RuntimeError if an attempt is made to join the current
            thread as that would cause a deadlock. It is also an error to join() a
            thread before it has been started and attempts to do so raises the same
            exception.

            """
            if not self._initialized:
                raise RuntimeError("Thread.__init__() not called")
            if not self._started.is_set():
                raise RuntimeError("cannot join thread before it is started")
            if self is current_thread():
                raise RuntimeError("cannot join current thread")

            if timeout is None:
                self._wait_for_tstate_lock()
            else:
                # the behavior of a negative timeout isn't documented, but
                # historically .join(timeout=x) for x<0 has acted as if timeout=0
                self._wait_for_tstate_lock(timeout=max(timeout, 0))
    ```

処理本体は `self._wait_for_tstate_lock()` .

- `self._wait_for_tstate_lock()`

    ```python
    # Lob/threading
    def _wait_for_tstate_lock(self, block=True, timeout=-1):
            # Issue #18808: wait for the thread state to be gone.
            # At the end of the thread's life, after all knowledge of the thread
            # is removed from C data structures, C code releases our _tstate_lock.
            # This method passes its arguments to _tstate_lock.acquire().
            # If the lock is acquired, the C code is done, and self._stop() is
            # called.  That sets ._is_stopped to True, and ._tstate_lock to None.
            lock = self._tstate_lock
            if lock is None:  # already determined that the C code is done
                assert self._is_stopped
            elif lock.acquire(block, timeout):
                lock.release()
                self._stop()
    ```

`self._tstate_lock` をロックしてみて、ロックが獲得できたらスレッドが死んでいると判断しているらしい。 `self._stop()` はつまらない片付け処理だった。

### `_tstate_lock` の初期化、獲得

`self._tstate_lock` がどこで初期化されているか確認する。

まず、実際に `self._tstate_lock` へ値を代入しているのは `_set_tstate_lock()` である:

- `_set_tstate_lock()`

    ```python
    # Lib/threading.py:903
    def _set_tstate_lock(self):
            """
            Set a lock object which will be released by the interpreter when
            the underlying thread state (see pystate.h) gets deleted.
            """
            self._tstate_lock = _set_sentinel()
            self._tstate_lock.acquire()

            if not self.daemon:
                with _shutdown_locks_lock:
                    _shutdown_locks.add(self._tstate_lock)
    ```

ロックに `_set_sentinel()` の返り値を代入した後に、ロックを獲得している。

`_set_tstate_lock()` の呼び出し元は `_bootstrap_inner()` であり、ネイティブスレッドの生成後、実際にアプリケーションコードを走らせ始める直前にロックを作成していることがわかる。

続いて、 `_set_sentinel()` を見ていく。実体は:

- `_set_sentinel`

    ```python
    # Lib/threading.py:32
    # Rename some stuff so "from threading import *" is safe
    _start_new_thread = _thread.start_new_thread
    _allocate_lock = _thread.allocate_lock
    _set_sentinel = _thread._set_sentinel
    get_ident = _thread.get_ident
    ```

`_threading` モジュールのメソッドテーブルを確認すると、実装は `thread__set_sentinel` である:

- `thread_set_sentinel()`

    ```c
    // Modules/_threadmodule.c:1211
    static PyObject *
    thread__set_sentinel(PyObject *self, PyObject *Py_UNUSED(ignored))
    {
        PyObject *wr;
        PyThreadState *tstate = PyThreadState_Get();
        lockobject *lock;

        if (tstate->on_delete_data != NULL) {
            /* We must support the re-creation of the lock from a
               fork()ed child. */
            assert(tstate->on_delete == &release_sentinel);
            wr = (PyObject *) tstate->on_delete_data;
            tstate->on_delete = NULL;
            tstate->on_delete_data = NULL;
            Py_DECREF(wr);
        }
        lock = newlockobject();
        if (lock == NULL)
            return NULL;
        /* The lock is owned by whoever called _set_sentinel(), but the weakref
           hangs to the thread state. */
        wr = PyWeakref_NewRef((PyObject *) lock, NULL);
        if (wr == NULL) {
            Py_DECREF(lock);
            return NULL;
        }
        tstate->on_delete_data = (void *) wr;
        tstate->on_delete = &release_sentinel;
        return (PyObject *) lock;
    }
    ```

Python から叩けるロックは `lockobject` 型のようである。まずは、この `lockobject` について確認する。

### `lockobject`

タイプオブジェクト、メソッド定義を見る:

- `PyTypeObject Locktype`

    ```c
    // Modules/_threadmodule.c:228
    static PyTypeObject Locktype = {
        PyVarObject_HEAD_INIT(&PyType_Type, 0)
        "_thread.lock",                     /*tp_name*/
        sizeof(lockobject),                 /*tp_basicsize*/
        0,                                  /*tp_itemsize*/
        /* methods */
        (destructor)lock_dealloc,           /*tp_dealloc*/
        0,                                  /*tp_vectorcall_offset*/
        0,                                  /*tp_getattr*/
        0,                                  /*tp_setattr*/
        0,                                  /*tp_as_async*/
        (reprfunc)lock_repr,                /*tp_repr*/
        0,                                  /*tp_as_number*/
        0,                                  /*tp_as_sequence*/
        0,                                  /*tp_as_mapping*/
        0,                                  /*tp_hash*/
        0,                                  /*tp_call*/
        0,                                  /*tp_str*/
        0,                                  /*tp_getattro*/
        0,                                  /*tp_setattro*/
        0,                                  /*tp_as_buffer*/
        Py_TPFLAGS_DEFAULT,                 /*tp_flags*/
        0,                                  /*tp_doc*/
        0,                                  /*tp_traverse*/
        0,                                  /*tp_clear*/
        0,                                  /*tp_richcompare*/
        offsetof(lockobject, in_weakreflist), /*tp_weaklistoffset*/
        0,                                  /*tp_iter*/
        0,                                  /*tp_iternext*/
        lock_methods,                       /*tp_methods*/
    };
    ```

- `PyMethodDef lock_methods`

    ```c
    // Modules/_threadmodule.c:208
    static PyMethodDef lock_methods[] = {
        {"acquire_lock", (PyCFunction)(void(*)(void))lock_PyThread_acquire_lock,
         METH_VARARGS | METH_KEYWORDS, acquire_doc},
        {"acquire",      (PyCFunction)(void(*)(void))lock_PyThread_acquire_lock,
         METH_VARARGS | METH_KEYWORDS, acquire_doc},
        {"release_lock", (PyCFunction)lock_PyThread_release_lock,
         METH_NOARGS, release_doc},
        {"release",      (PyCFunction)lock_PyThread_release_lock,
         METH_NOARGS, release_doc},
        {"locked_lock",  (PyCFunction)lock_locked_lock,
         METH_NOARGS, locked_doc},
        {"locked",       (PyCFunction)lock_locked_lock,
         METH_NOARGS, locked_doc},
        {"__enter__",    (PyCFunction)(void(*)(void))lock_PyThread_acquire_lock,
         METH_VARARGS | METH_KEYWORDS, acquire_doc},
        {"__exit__",    (PyCFunction)lock_PyThread_release_lock,
         METH_VARARGS, release_doc},
        {NULL,           NULL}              /* sentinel */
    };
    ```

- `struct lockobject`

    ```c
    // Modules/_threadmodule.c:19
    typedef struct {
        PyObject_HEAD
        PyThread_type_lock lock_lock;
        PyObject *in_weakreflist;
        char locked; /* for sanity checking */
    } lockobject;
    ```

`acquire`, `release` された際の動作を見る。

- `lock_PyThread_acquire_lock()`

    ```c
    // Modules/_threadmodule.c:137
    static PyObject *
    lock_PyThread_acquire_lock(lockobject *self, PyObject *args, PyObject *kwds)
    {
        _PyTime_t timeout;
        PyLockStatus r;

        if (lock_acquire_parse_args(args, kwds, &timeout) < 0)
            return NULL;

        r = acquire_timed(self->lock_lock, timeout);
        if (r == PY_LOCK_INTR) {
            return NULL;
        }

        if (r == PY_LOCK_ACQUIRED)
            self->locked = 1;
        return PyBool_FromLong(r == PY_LOCK_ACQUIRED);
    }
    ```

本質は `acquire_timed()` ぽい。

- `acquire_timed()`

    ```c
    // Modules/_threadmodule.c:46
    static PyLockStatus
    acquire_timed(PyThread_type_lock lock, _PyTime_t timeout)
    {
        PyLockStatus r;
        _PyTime_t endtime = 0;
        _PyTime_t microseconds;

        if (timeout > 0)
            endtime = _PyTime_GetMonotonicClock() + timeout;

        do {
            microseconds = _PyTime_AsMicroseconds(timeout, _PyTime_ROUND_CEILING);

            /* first a simple non-blocking try without releasing the GIL */
            r = PyThread_acquire_lock_timed(lock, 0, 0);
            if (r == PY_LOCK_FAILURE && microseconds != 0) {
                Py_BEGIN_ALLOW_THREADS
                r = PyThread_acquire_lock_timed(lock, microseconds, 1);
                Py_END_ALLOW_THREADS
            }

            if (r == PY_LOCK_INTR) {
                /* Run signal handlers if we were interrupted.  Propagate
                 * exceptions from signal handlers, such as KeyboardInterrupt, by
                 * passing up PY_LOCK_INTR.  */
                if (Py_MakePendingCalls() < 0) {
                    return PY_LOCK_INTR;
                }

                /* If we're using a timeout, recompute the timeout after processing
                 * signals, since those can take time.  */
                if (timeout > 0) {
                    timeout = endtime - _PyTime_GetMonotonicClock();

                    /* Check for negative values, since those mean block forever.
                     */
                    if (timeout < 0) {
                        r = PY_LOCK_FAILURE;
                    }
                }
            }
        } while (r == PY_LOCK_INTR);  /* Retry if we were interrupted. */

        return r;
    }
    ```

`PyThread_acquire_lock_timed()` は実装が2つあり、以下のマクロによってどちらの実装を利用するか決められる:

```c
// Python/thread_pthread.h:77
/* Whether or not to use semaphores directly rather than emulating them with
 * mutexes and condition variables:
 */
#if (defined(_POSIX_SEMAPHORES) && !defined(HAVE_BROKEN_POSIX_SEMAPHORES) && \
     defined(HAVE_SEM_TIMEDWAIT))
#  define USE_SEMAPHORES
#else
#  undef USE_SEMAPHORES
#endif
```

今回の環境は `POSIX SEMAPHORE` が使えるのでそちらの実装を確認する。

- `PyThread_acquire_lock_timed()`

    ```c
    PyLockStatus
    PyThread_acquire_lock_timed(PyThread_type_lock lock, PY_TIMEOUT_T microseconds,
                                int intr_flag)
    {
        PyLockStatus success;
        sem_t *thelock = (sem_t *)lock;
        int status, error = 0;
        struct timespec ts;
        _PyTime_t deadline = 0;

        (void) error; /* silence unused-but-set-variable warning */
        dprintf(("PyThread_acquire_lock_timed(%p, %lld, %d) called\n",
                 lock, microseconds, intr_flag));

        if (microseconds > PY_TIMEOUT_MAX) {
            Py_FatalError("Timeout larger than PY_TIMEOUT_MAX");
        }

        if (microseconds > 0) {
            MICROSECONDS_TO_TIMESPEC(microseconds, ts);

            if (!intr_flag) {
                /* cannot overflow thanks to (microseconds > PY_TIMEOUT_MAX)
                   check done above */
                _PyTime_t timeout = _PyTime_FromNanoseconds(microseconds * 1000);
                deadline = _PyTime_GetMonotonicClock() + timeout;
            }
        }

        while (1) {
            if (microseconds > 0) {
                status = fix_status(sem_timedwait(thelock, &ts));
            }
            else if (microseconds == 0) {
                status = fix_status(sem_trywait(thelock));
            }
            else {
                status = fix_status(sem_wait(thelock));
            }

            /* Retry if interrupted by a signal, unless the caller wants to be
               notified.  */
            if (intr_flag || status != EINTR) {
                break;
            }

            if (microseconds > 0) {
                /* wait interrupted by a signal (EINTR): recompute the timeout */
                _PyTime_t dt = deadline - _PyTime_GetMonotonicClock();
                if (dt < 0) {
                    status = ETIMEDOUT;
                    break;
                }
                else if (dt > 0) {
                    _PyTime_t realtime_deadline = _PyTime_GetSystemClock() + dt;
                    if (_PyTime_AsTimespec(realtime_deadline, &ts) < 0) {
                        /* Cannot occur thanks to (microseconds > PY_TIMEOUT_MAX)
                           check done above */
                        Py_UNREACHABLE();
                    }
                    /* no need to update microseconds value, the code only care
                       if (microseconds > 0 or (microseconds == 0). */
                }
                else {
                    microseconds = 0;
                }
            }
        }
    ```

タイムアウトの残り時間に応じて `sem_timedwait` , `sem_trywait` , `sem_wait` を使い分ける。

いずれも、POSIX SEMAPHORE として提供されている:

[SEMAPHORES](https://linuxjm.osdn.jp/html/glibc-linuxthreads/man3/sem_init.3.html)

[SEM_WAIT](https://linuxjm.osdn.jp/html/LDP_man-pages/man3/sem_wait.3.html)

- `sem_wait` : セマフォ減算。ブロッキング。
- `sem_trywait` : セマフォ減算。ノンブロッキング。
- `sem_timedwait` : セマフォ減算。ブロックのタイムアウトを設定可能。

つまり、 `lockobject` の `acquire` は、セマフォを獲得する。

続いて、 `release` を見る。

- `lock_PyThread_release_lock()`

    ```c
    // Modules/_threadmodule.c:167
    static PyObject *
    lock_PyThread_release_lock(lockobject *self, PyObject *Py_UNUSED(ignored))
    {
        /* Sanity check: the lock must be locked */
        if (!self->locked) {
            PyErr_SetString(ThreadError, "release unlocked lock");
            return NULL;
        }

        PyThread_release_lock(self->lock_lock);
        self->locked = 0;
        Py_RETURN_NONE;
    }

    PyDoc_STRVAR(release_doc,
    "release()\n\
    (release_lock() is an obsolete synonym)\n\
    \n\
    Release the lock, allowing another thread that is blocked waiting for\n\
    the lock to acquire the lock.  The lock must be in the locked state,\n\
    but it needn't be locked by the same thread that unlocks it.");
    ```

- `PyThread_release_lock()`

    ```c
    void
    PyThread_release_lock(PyThread_type_lock lock)
    {
        sem_t *thelock = (sem_t *)lock;
        int status, error = 0;

        (void) error; /* silence unused-but-set-variable warning */
        dprintf(("PyThread_release_lock(%p) called\n", lock));

        status = sem_post(thelock);
        CHECK_STATUS("sem_post");
    }
    ```

`sem_post` も POSIX SEMAPHORE で提供されている機能である:

[SEM_POST](https://linuxjm.osdn.jp/html/LDP_man-pages/man3/sem_post.3.html)

- `sem_post` : セマフォ加算。ブロックしない。

つまり、 `lockobject` は OS のロック / セマフォ機構のラッパーである。

### `_tstate_lock` の呼び出し

では、 `_tstate_lock` の解放はどこで行われているのだろうか。

実は、 `Thread._set_tstate_lock()` → `Thread._set_sentinel()` → `thread_set_sentinel()` において、スレッド消滅時にロックを解放するようにイベントハンドラが登録されている:

```c
// Modules/_threadmodule.c:1211
static PyObject *
thread__set_sentinel(PyObject *self, PyObject *Py_UNUSED(ignored))
{
		...
    tstate->on_delete_data = (void *) wr;
    tstate->on_delete = &release_sentinel;
    return (PyObject *) lock;
}
```

- `release_sentinel()`

    ```c
    // Modules/_threadmodule.c:1189
    static void
    release_sentinel(void *wr_raw)
    {
        PyObject *wr = _PyObject_CAST(wr_raw);
        /* Tricky: this function is called when the current thread state
           is being deleted.  Therefore, only simple C code can safely
           execute here. */
        PyObject *obj = PyWeakref_GET_OBJECT(wr);
        lockobject *lock;
        if (obj != Py_None) {
            assert(Py_TYPE(obj) == &Locktype);
            lock = (lockobject *) obj;
            if (lock->locked) {
                PyThread_release_lock(lock->lock_lock);
                lock->locked = 0;
            }
        }
        /* Deallocating a weakref with a NULL callback only calls
           PyObject_GC_Del(), which can't call any Python code. */
        Py_DECREF(wr);
    }
    ```

`PyThread_release_lock()` を呼び出し、ロックを解放している。

では、 `tstate->on_delete` ハンドラはどこで呼び出されているのだろうか。

これは、 `t_bootstrap()` の末尾のスレッド終了処理にて行われている。 `t_bootstrap()` は別スレッド生成時に真っ先に実行される関数であった:

```c
// Modules/_threadmodule.c:990
static void
t_bootstrap(void *boot_raw)
{
    ...
    PyThreadState_Clear(tstate);
    PyThreadState_DeleteCurrent();
    PyThread_exit_thread();
}
```

- `PyThreadState_DeleteCurrent()`

    ```c
    // Python/pystate.c:875
    void
    PyThreadState_DeleteCurrent()
    {
        _PyThreadState_DeleteCurrent(&_PyRuntime);
    }
    ```

- `_PyThreadState_DeleteCurrent()`

    ```c
    // Python/pystate.c:857
    static void
    _PyThreadState_DeleteCurrent(_PyRuntimeState *runtime)
    {
        struct _gilstate_runtime_state *gilstate = &runtime->gilstate;
        PyThreadState *tstate = _PyRuntimeGILState_GetThreadState(gilstate);
        if (tstate == NULL)
            Py_FatalError(
                "PyThreadState_DeleteCurrent: no current tstate");
        tstate_delete_common(runtime, tstate);
        if (gilstate->autoInterpreterState &&
            PyThread_tss_get(&gilstate->autoTSSkey) == tstate)
        {
            PyThread_tss_set(&gilstate->autoTSSkey, NULL);
        }
        _PyRuntimeGILState_SetThreadState(gilstate, NULL);
        PyEval_ReleaseLock();
    }
    ```

- `tstate_delete_common()`

    ```c
    // Python/pystate.c:808
    /* Common code for PyThreadState_Delete() and PyThreadState_DeleteCurrent() */
    static void
    tstate_delete_common(_PyRuntimeState *runtime, PyThreadState *tstate)
    {
        if (tstate == NULL) {
            Py_FatalError("PyThreadState_Delete: NULL tstate");
        }
        PyInterpreterState *interp = tstate->interp;
        if (interp == NULL) {
            Py_FatalError("PyThreadState_Delete: NULL interp");
        }
        HEAD_LOCK(runtime);
        if (tstate->prev)
            tstate->prev->next = tstate->next;
        else
            interp->tstate_head = tstate->next;
        if (tstate->next)
            tstate->next->prev = tstate->prev;
        HEAD_UNLOCK(runtime);
        if (tstate->on_delete != NULL) {
            tstate->on_delete(tstate->on_delete_data);
        }
        PyMem_RawFree(tstate);
    }
    ```

ここで `tstate->on_delete` に `tstate->on_delete_data` が渡されて実行されていることがわかる。

### まとめ

- 別スレッドが生成され、アプリケーションコードが走る直前にロックが獲得される
- アプリケーションコードの実行が終わり、スレッドが死ぬ寸前にロックが解放される
- `Thread.join()` は、このロックに対してブロッキングの獲得を試みることで、スレッドが終了するまで処理をブロックしている

# 参考

[【CPython3.6源码分析】Python 多线程机制](https://he11olx.com/2018/08/04/1.CPython3.6%E6%BA%90%E7%A0%81%E5%88%86%E6%9E%90/1.13.Python%20%E5%A4%9A%E7%BA%BF%E7%A8%8B%E6%9C%BA%E5%88%B6/)

---

[[draft] threading internal](https://www.notion.so/draft-threading-internal-c4fb99db9a554259b513d1d5ebbc1888)