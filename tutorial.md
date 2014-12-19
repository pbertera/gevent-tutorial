[TOC]

# Introduzione

La struttura di questo tutorial richiede solamente un livello intermedio
di conoscenza di Python. Non non sono necessarie conoscenze specifiche su temi di concorrenza. L'obiettivo e' quello di fornirti gli strumenti necessari per lavorare con gevent, aiutarti nel gestire problemi di concorrenza ed iniziare a scrivere codice asincrono oggi.

### Contributi

Nell' ordine cronologico di aiuto:
[Stephen Diehl](http://www.stephendiehl.com)
[J&eacute;r&eacute;my Bethmont](https://github.com/jerem)
[sww](https://github.com/sww)
[Bruno Bigras](https://github.com/brunoqc)
[David Ripton](https://github.com/dripton)
[Travis Cline](https://github.com/traviscline)
[Boris Feld](https://github.com/Lothiraldan)
[youngsterxyf](https://github.com/youngsterxyf)
[Eddie Hebert](https://github.com/ehebert)
[Alexis Metaireau](http://notmyidea.org)
[Daniel Velkov](https://github.com/djv)

Grazie anche a Denis Bilenko per aver scritto gevent ed avermi seguito nella scrittura di questo tutorial.

Questo e' un documento scritto in collaborazione e pubblicato con licenza MIT.
Vuoi aggiungere qualcosa ? Hai trovato un errore ? Fai un fork e richiedi un pull Github](https://github.com/sdiehl/gevent-tutorial).
Qualsiasi contributo e' benvenuto.

Questa pagina e' anche [disponibile in Japanese](http://methane.github.com/gevent-tutorial-ja).

# Core

## Greenlets

Il modello principale utilizzato in gevent e' <strong>Greenlet</strong>,
un'implementazione di coroutine per Python fornita come extension module in C.
Le Greenlets girano tutte all'interno del processo del programma principale ma sono schedulate in maniera cooperativa.

> Sempre e solo una greenlet e' in esecuzione in un data momento.

Questo concetto e' diverso da tutti i modelli di parallelismo forniti da librerie di ``multiprocessing`` o ``threading`` che lanciano processi e thread POSIX schedulati dal sistema operativo e veramente paralleli.

## Esecuzione sincrona & asincrona

L'idea principale della concorrenza e' che un grande task puo' essere spezzato in un'insieme di piccoli sotto-task che vengono fatti girare contemporaneamente o in maniera *asincrona*, invece di uno alla volta in maniera *sincrona*. Il passaggio da un sotto-task a un altro viene detto *context switch*.

Un context switch in gevent avviene tramite *yelding* (precedenze). In questo esempio abbiamo due contesti che si danno la precedenza a vicenda invocando ``gevent.sleep(0)``.

[[[cog
import gevent

def foo():
    print('Running in foo')
    gevent.sleep(0)
    print('Explicit context switch to foo again')

def bar():
    print('Explicit context to bar')
    gevent.sleep(0)
    print('Implicit context switch back to bar')

gevent.joinall([
    gevent.spawn(foo),
    gevent.spawn(bar),
])
]]]
[[[end]]]

Quest'immagine visualizza chiaramente il flusso del programma oppure e' possibile utilizzare un debugger per vedere i context switch e quando avvengono.

![Greenlet Control Flow](flow.gif)

La vera potenza di gevent quando lo usiamo per delle funzioni di rete e di IO che possono essere schedulate in maniera cooperativa. Gevent si e' preso cura di tutti i dettagli per assicurare che le tue librerie di rete daranno implicitamente la precedenza al loro greenlet context appena possibile. Non posso stressare a sufficienza per rendere l'idea di quanto e' potente questo paradigma.
Forse un esempio puo' illustrarlo.

In questo caso la funzione ``select()`` e' normalmente una chiamata bloccante che interroga vari file descriptor.

[[[cog
import time
import gevent
from gevent import select

start = time.time()
tic = lambda: 'at %1.1f seconds' % (time.time() - start)

def gr1():
    # Busy waits for a second, but we don't want to stick around...
    print('Started Polling: %s' % tic())
    select.select([], [], [], 2)
    print('Ended Polling: %s' % tic())

def gr2():
    # Busy waits for a second, but we don't want to stick around...
    print('Started Polling: %s' % tic())
    select.select([], [], [], 2)
    print('Ended Polling: %s' % tic())

def gr3():
    print("Hey lets do some stuff while the greenlets poll, %s" % tic())
    gevent.sleep(1)

gevent.joinall([
    gevent.spawn(gr1),
    gevent.spawn(gr2),
    gevent.spawn(gr3),
])
]]]
[[[end]]]

Un altro sintetico esempio definisce una funzione ``task`` non deterministica (ovvero non garantisce dare sempre lo stesso output per il medesimo input).
In questo caso l'effetto collaterale e' che il task fermera' l'esecuzione per un numero random di secondi.

[[[cog
import gevent
import random

def task(pid):
    """
    Some non-deterministic task
    """
    gevent.sleep(random.randint(0,2)*0.001)
    print('Task %s done' % pid)

def synchronous():
    for i in range(1,10):
        task(i)

def asynchronous():
    threads = [gevent.spawn(task, i) for i in xrange(10)]
    gevent.joinall(threads)

print('Synchronous:')
synchronous()

print('Asynchronous:')
asynchronous()
]]]
[[[end]]]

Nel caso sincrono tutti i task sono lanciati in maniera sequenziale, facendo cosi' che il programma principale rimanga in stato *blocking* (rimane bloccato finche' non e' terminato ogni task) durante l'esecuzione dei task.

La parte importante del programma e' il ``gevent.spawn`` che include la funzione passata all'interno di un Greenlet thread. La lista delle greenlet inizializzate viene salvata nell'array ``threads`` il quale viene passato alla funzione ``gevent.joinall`` la quale blocca l'esecuzione del programma corrente e lancia tutte le greenlet ricevute. L'esecuzione del programma principale riprendera' quando tutte le greenlet sono terminate.

E' importante notare il fatto che l'ordine di esecuzione delle greenlet nel caso asincrono e' essenzialmente random e il tempo totale di esecuzione in modalita' asincrona e' di molto minore della modalita' sincrona. Infatti il massimo tempo di esecuzione nel caso sincrono e' quando ogni task si ferma per 0.002 secondi, facendo cosi' un totale di 0.02 secondi per l'intera coda. Nel caso asincrono il tempo massimo impiegato sara' all'incirca di 0.002 secondi perche' nessuno dei task blocca l'esecuzione degli altri.

In uno use-case piu' comune, ricevendo dati in maniera asincrona da un server, il tempo di esecuzione di ``fetch()` sara' differente per ogni richiesta, in funzione del carico sul server remoto nel momento della richiesta.
at the time of the request.

<pre><code class="python">import gevent.monkey
gevent.monkey.patch_socket()

import gevent
import urllib2
import simplejson as json

def fetch(pid):
    response = urllib2.urlopen('http://json-time.appspot.com/time.json')
    result = response.read()
    json_result = json.loads(result)
    datetime = json_result['datetime']

    print('Process %s: %s' % (pid, datetime))
    return json_result['datetime']

def synchronous():
    for i in range(1,10):
        fetch(i)

def asynchronous():
    threads = []
    for i in range(1,10):
        threads.append(gevent.spawn(fetch, i))
    gevent.joinall(threads)

print('Synchronous:')
synchronous()

print('Asynchronous:')
asynchronous()
</code>
</pre>

## Determinismo

Come detto prima, le greenlets sono deterministiche. Data la medesima configurazione di greenlet e lo stesso set di input, loro produrranno lo stesso output. Per esempio, distribuiamo l'esecuzione di un task su di un multiprocessing pool e compariamo il risultato con quello di un greenlet pool.

<pre>
<code class="python">
import time

def echo(i):
    time.sleep(0.001)
    return i

# Non Deterministic Process Pool

from multiprocessing.pool import Pool

p = Pool(10)
run1 = [a for a in p.imap_unordered(echo, xrange(10))]
run2 = [a for a in p.imap_unordered(echo, xrange(10))]
run3 = [a for a in p.imap_unordered(echo, xrange(10))]
run4 = [a for a in p.imap_unordered(echo, xrange(10))]

print(run1 == run2 == run3 == run4)

# Deterministic Gevent Pool

from gevent.pool import Pool

p = Pool(10)
run1 = [a for a in p.imap_unordered(echo, xrange(10))]
run2 = [a for a in p.imap_unordered(echo, xrange(10))]
run3 = [a for a in p.imap_unordered(echo, xrange(10))]
run4 = [a for a in p.imap_unordered(echo, xrange(10))]

print(run1 == run2 == run3 == run4)
</code>
</pre>

<pre>
<code class="python">False
True</code>
</pre>

Nonostante gevent sia normalmente deterministica, sorgenti di non-determinismo potrebbero insinuarsi nel programma quando inizi ad interagire con servizi esterni come socket o file. Quindi nonostante i green thread siano una forma di "deterministic concurrency", possono essere comunque affetti dagli stessi problemi dei thread POSIX e dei processi.

Il perenne problema legato alla concorrenza e' noto come *race condition*. Semplificando, una race condition avviene quando due thread concorrenti / processi dipendono dalla stessa risorsa condivisa ed entrambi provano a modificarne il valore. Questo finira' con delle risorse il cui valore diventa dipendente nel tempo dall'ordine di esecuzione. Questo e' un problema ed in generale si dovrebbe cercare di evitare race condition in quanto portano il risultato ad un comportamento non deterministico. 

Il migliore approccio e' quello di evitare sempre tutti gli stati globali. Gli effetti collaterali di stati globali e tempi di import torneranno sempre per morderti!

## Lanciare Greenlets

gevent fornisce alcuni wrapper attorno all'inizializzazione delle Greenlet.
Alcuni dei modelli piu' comuni sono:

[[[cog
import gevent
from gevent import Greenlet

def foo(message, n):
    """
    Each thread will be passed the message, and n arguments
    in its initialization.
    """
    gevent.sleep(n)
    print(message)

# Initialize a new Greenlet instance running the named function
# foo
thread1 = Greenlet.spawn(foo, "Hello", 1)

# Wrapper for creating and running a new Greenlet from the named
# function foo, with the passed arguments
thread2 = gevent.spawn(foo, "I live!", 2)

# Lambda expressions
thread3 = gevent.spawn(lambda x: (x+1), 2)

threads = [thread1, thread2, thread3]

# Block until all threads complete.
gevent.joinall(threads)
]]]
[[[end]]]

Oltre ad utilizzate la classe base Greenlet, si puo' anche fare subclassing e sovrascrivere il metodo ``_run``.

[[[cog
import gevent
from gevent import Greenlet

class MyGreenlet(Greenlet):

    def __init__(self, message, n):
        Greenlet.__init__(self)
        self.message = message
        self.n = n

    def _run(self):
        print(self.message)
        gevent.sleep(self.n)

g = MyGreenlet("Hi there!", 3)
g.start()
g.join()
]]]
[[[end]]]


## Stato della Greenlet

Come ogni altra parte di codice, una Greenlet puo' fallire in vari modi. Una greenlet puo' fallire lanciando un'eccezione, bloccarsi oppure consumare troppe risorse di sistema.

Lo stato interno di una greenlet e' in genere un parametro dipendente dal tempo. Ci sono alcuni flag nelle greenlet che permettono di monitorare lo stato del thread:

- ``started`` -- Booleano, indica se la Greenlet e' partita
- ``ready()`` -- Booleano, indica se la Greenlet si e' fermata
- ``successful()`` -- Booleano, indica se la Greenlet si e' fermata senza sollevare eccezzioni
- ``value`` -- arbitrario, il valore ritornato dalla greenlet
- ``exception`` -- eccezione, eccezione non gestita sollevata all'interno della greenlet

[[[cog
import gevent

def win():
    return 'You win!'

def fail():
    raise Exception('You fail at failing.')

winner = gevent.spawn(win)
loser = gevent.spawn(fail)

print(winner.started) # True
print(loser.started)  # True

# Exceptions raised in the Greenlet, stay inside the Greenlet.
try:
    gevent.joinall([winner, loser])
except Exception as e:
    print('This will never be reached')

print(winner.value) # 'You win!'
print(loser.value)  # None

print(winner.ready()) # True
print(loser.ready())  # True

print(winner.successful()) # True
print(loser.successful())  # False

# The exception raised in fail, will not propagate outside the
# greenlet. A stack trace will be printed to stdout but it
# will not unwind the stack of the parent.

print(loser.exception)

# It is possible though to raise the exception again outside
# raise loser.exception
# or with
# loser.get()
]]]
[[[end]]]

## Spegnimento del programma

Greenlets che falliscono nello yeld mentre il programma principale riceve un segnale SIGQUIT potrebbero trattenere l'esecuzione del programma per un tempo piu' lungo dell'aspettato. Questo finira' per creare un "processo zombie" che deve essere ucciso fuori dall'interprete Python.

Un modello comune e' quello di gestire i segnali SIGQUIT nel programma principale e invocare ``gevent.shutdown`` prima di uscire.

<pre>
<code class="python">import gevent
import signal

def run_forever():
    gevent.sleep(1000)

if __name__ == '__main__':
    gevent.signal(signal.SIGQUIT, gevent.kill)
    thread = gevent.spawn(run_forever)
    thread.join()
</code>
</pre>

## Timeout

Timeout sono dei limiti di tempo di esecuzione di un pezzo di codice o una Greenlet.

<pre>
<code class="python">
import gevent
from gevent import Timeout

seconds = 10

timeout = Timeout(seconds)
timeout.start()

def wait():
    gevent.sleep(10)

try:
    gevent.spawn(wait).join()
except Timeout:
    print('Could not complete')

</code>
</pre>

I timeout possono anche essere usati con un context manager all'interno di una direttiva ``with``.

<pre>
<code class="python">import gevent
from gevent import Timeout

time_to_wait = 5 # seconds

class TooLong(Exception):
    pass

with Timeout(time_to_wait, TooLong):
    gevent.sleep(10)
</code>
</pre>

Inoltre, gevent fornisce argomenti di timeout per diverse Greenlet, strutture dati e relative chiamate. Per esempio:

[[[cog
import gevent
from gevent import Timeout

def wait():
    gevent.sleep(2)

timer = Timeout(1).start()
thread1 = gevent.spawn(wait)

try:
    thread1.join(timeout=timer)
except Timeout:
    print('Thread 1 timed out')

# --

timer = Timeout.start_new(1)
thread2 = gevent.spawn(wait)

try:
    thread2.get(timeout=timer)
except Timeout:
    print('Thread 2 timed out')

# --

try:
    gevent.with_timeout(1, wait)
except Timeout:
    print('Thread 3 timed out')

]]]
[[[end]]]

## Monkeypatching

Purtroppo siamo giunti al lato oscuro di Gevent. Ho evitato di menzionarlo fino ad ora il monkey patching per cercare di motivare la potenza del modello "coroutine", ma ora dobbiamo parlare dell'arte oscura del monkey-patching. Se avete notato prima e' stato invocato il comando ``monkey.patch_socket()``. Questo e' un comando che modifica la socket standard library.

<pre>
<code class="python">import socket
print(socket.socket)

print("After monkey patch")
from gevent import monkey
monkey.patch_socket()
print(socket.socket)

import select
print(select.select)
monkey.patch_select()
print("After monkey patch")
print(select.select)
</code>
</pre>

<pre>
<code class="python">class 'socket.socket'
After monkey patch
class 'gevent.socket.socket'

built-in function select
After monkey patch
function select at 0x1924de8
</code>
</pre>

L'ambiente Python permette di modificare a runtime molti oggetti: moduli, classi ed anche funzioni. In generale questa e' assolutamente una cattiva idea perche' crea un "implicito effetto collaterale" che spesso e' difficile da debuggare, tuttavia in situazioni estreme in cui una libreria deve alterare dei comportamenti base di Python il monkey-patching puo' essere utilizzato. In questo caso gevent e' in grado di "patchare" la gran parte delle systemm call bloccanti nella standard library includendo i moduli ``socket``, ``ssl``, ``threading`` e ``select`` rendendoli in grado di operare in maniera cooperativa.
Per esempio, i binding Python per Redis usano normalmente dei socket tcp normali per comunicare con un istanza del server redis. Semplicemente invocando ``gevent.monkey.patch_all()`` e' possibile fare in modo che i binding redis schedulino richieste cooperative e possono lavorare con i nostro gevent stack.

Questo ci permette di integrare librerie che di solito non lavorano con gevent senza dover scrivere una linea di codice. Siccome il monkey-patching e' sempre il male, in questo caso e' un "male utile".

# Strutture Dati

## Eventi

Gli eventi sono una forma di comunicazione asincrona tra le Greenlets.

<pre>
<code class="python">import gevent
from gevent.event import Event

'''
Illustrates the use of events
'''


evt = Event()

def setter():
    '''After 3 seconds, wake all threads waiting on the value of evt'''
	print('A: Hey wait for me, I have to do something')
	gevent.sleep(3)
	print("Ok, I'm done")
	evt.set()


def waiter():
	'''After 3 seconds the get call will unblock'''
	print("I'll wait for you")
	evt.wait()  # blocking
	print("It's about time")

def main():
	gevent.joinall([
		gevent.spawn(setter),
		gevent.spawn(waiter),
		gevent.spawn(waiter),
		gevent.spawn(waiter),
		gevent.spawn(waiter),
		gevent.spawn(waiter)
	])

if __name__ == '__main__': main()

</code>
</pre>

Un estensione dell'oggetto Event e' AsyncResult il quale permette di inviare un valore tramite una chiamata di wakeup. Questo viene chiamato anche future o deferred perche' ha un riferimento ad un valore futuro che puo' essere impostato in un momento arbitrario.

<pre>
<code class="python">import gevent
from gevent.event import AsyncResult
a = AsyncResult()

def setter():
    """
    After 3 seconds set the result of a.
    """
    gevent.sleep(3)
    a.set('Hello!')

def waiter():
    """
    After 3 seconds the get call will unblock after the setter
    puts a value into the AsyncResult.
    """
    print(a.get())

gevent.joinall([
    gevent.spawn(setter),
    gevent.spawn(waiter),
])

</code>
</pre>

## Code

Le code sono degli insiemi ordinati di dati che hanno le solite operazioni ``put`` / ``get` ma sono scritte in modo da essere manipolati tramite delle Greenlet.

Per esempio se una greenlet toglie un componente da una coda, lo stesso componente non potra' essere prelevato da un'altra greenlet che sta girando contemporaneamente.

[[[cog
import gevent
from gevent.queue import Queue

tasks = Queue()

def worker(n):
    while not tasks.empty():
        task = tasks.get()
        print('Worker %s got task %s' % (n, task))
        gevent.sleep(0)

    print('Quitting time!')

def boss():
    for i in xrange(1,25):
        tasks.put_nowait(i)

gevent.spawn(boss).join()

gevent.joinall([
    gevent.spawn(worker, 'steve'),
    gevent.spawn(worker, 'john'),
    gevent.spawn(worker, 'nancy'),
])
]]]
[[[end]]]

Le code possono bloccare sia ``put`` che ``get`` se ce n'e' la necessita'.

Le operazioni di ``put`` e ``get`` hanno la loro controparte non bloccante: ``put_nowait`` e ``get_nowait`` che non bloccano l'esecuzione ma invece sollevano le eccezioni ``gevent.queue.Empty`` o ``gevent.queue.Full`` se l'operazione non e' possibile.

In questo esempio abbiamo boss che gira in contemporanea con i workers e c'e' un limite sulla coda che impedisce di avere piu' di tre elementi. Questo limite significa che l'operazione ``put`` rimarra' bloccata finche' non ci sara' spazio nella coda. All'inverso la ``get`` rimarra' bloccata se non ci sono elementi da prelevare nella coda, riceve anche un timeout per permettere che la funzione termini con l'eccezione ``gevent.queue.Empty`` se non puo' essere trovato nulla nell'intervallo di Timeout.

[[[cog
import gevent
from gevent.queue import Queue, Empty

tasks = Queue(maxsize=3)

def worker(name):
    try:
        while True:
            task = tasks.get(timeout=1) # decrements queue size by 1
            print('Worker %s got task %s' % (name, task))
            gevent.sleep(0)
    except Empty:
        print('Quitting time!')

def boss():
    """
    Boss will wait to hand out work until a individual worker is
    free since the maxsize of the task queue is 3.
    """

    for i in xrange(1,10):
        tasks.put(i)
    print('Assigned all work in iteration 1')

    for i in xrange(10,20):
        tasks.put(i)
    print('Assigned all work in iteration 2')

gevent.joinall([
    gevent.spawn(boss),
    gevent.spawn(worker, 'steve'),
    gevent.spawn(worker, 'john'),
    gevent.spawn(worker, 'bob'),
])
]]]
[[[end]]]

## Gruppi e Pools

Un gruppo e' un insieme di greenlet in esecuzione gestite e schedulate assieme come gruppo. 
A group is a collection of running greenlets which are managed funge anche da dispatcher parallelo come la libreria ``multiprocessing``.

[[[cog
import gevent
from gevent.pool import Group

def talk(msg):
    for i in xrange(3):
        print(msg)

g1 = gevent.spawn(talk, 'bar')
g2 = gevent.spawn(talk, 'foo')
g3 = gevent.spawn(talk, 'fizz')

group = Group()
group.add(g1)
group.add(g2)
group.join()

group.add(g3)
group.join()
]]]
[[[end]]]

E' molto utile gestire gruppi di task asincroni.

Come detto prima, ``Group`` prevede anche un'API per fare dispatching di job a gruppi di greenlet e ricevere i risultati in vari modi.

[[[cog
import gevent
from gevent import getcurrent
from gevent.pool import Group

group = Group()

def hello_from(n):
    print('Size of group %s' % len(group))
    print('Hello from Greenlet %s' % id(getcurrent()))

group.map(hello_from, xrange(3))


def intensive(n):
    gevent.sleep(3 - n)
    return 'task', n

print('Ordered')

ogroup = Group()
for i in ogroup.imap(intensive, xrange(3)):
    print(i)

print('Unordered')

igroup = Group()
for i in igroup.imap_unordered(intensive, xrange(3)):
    print(i)

]]]
[[[end]]]

Un pool e' una struttura progettata per gestire un numero variabile di greenlet che necessitano di concorrenza limitata. Questo e' spesso necessario quando vogliamo effetuare molti task di rete o di IO.

[[[cog
import gevent
from gevent.pool import Pool

pool = Pool(2)

def hello_from(n):
    print('Size of pool %s' % len(pool))

pool.map(hello_from, xrange(3))
]]]
[[[end]]]

Spesso, quando si implementano servizi basati su gevent, tutto il servizio ruota attorno ad un pool. Un esempio potrebbe essere una classe che interroga vari sockets.

<pre>
<code class="python">from gevent.pool import Pool

class SocketPool(object):

    def __init__(self):
        self.pool = Pool(1000)
        self.pool.start()

    def listen(self, socket):
        while True:
            socket.recv()

    def add_handler(self, socket):
        if self.pool.full():
            raise Exception("At maximum pool size")
        else:
            self.pool.spawn(self.listen, socket)

    def shutdown(self):
        self.pool.kill()

</code>
</pre>

## Locks e Semafori

Un semaforo e' una primitiva a basso livello the permette alle greenlets di coordinare o limitare accessi o esecuzioni concorrenti. Un semaforo espone due metodi, ``acquire`` e ``release`` la differenza tra il numero di volte che un semaforo e' stato acquisito e rilasciato e' chiamato bound (intervallo) del semaforo. Se il bound di un semaforo arriva a 0 finche' un'altra greenlet non rilascia la sua acquisizione.

[[[cog
from gevent import sleep
from gevent.pool import Pool
from gevent.coros import BoundedSemaphore

sem = BoundedSemaphore(2)

def worker1(n):
    sem.acquire()
    print('Worker %i acquired semaphore' % n)
    sleep(0)
    sem.release()
    print('Worker %i released semaphore' % n)

def worker2(n):
    with sem:
        print('Worker %i acquired semaphore' % n)
        sleep(0)
    print('Worker %i released semaphore' % n)

pool = Pool()
pool.map(worker1, xrange(0,2))
pool.map(worker2, xrange(3,6))
]]]
[[[end]]]

Un semaforo con bound 1 e' detto Lock. Fornisce un esecuzione esclusiva nella greenlet. Sono spesso utilizzati per assicurarsi che una risorsa sia in uso una sola volta nel contesto di un programma.

## Thread Locali

Gevent permette anche di specificare dati che sono locali al contesto della greenlet. Internamete questo e' implementato come una ricerca globale che punta ad un namespace privato identificato dal valore ``getcurrent()`` della greenlet.

[[[cog
import gevent
from gevent.local import local

stash = local()

def f1():
    stash.x = 1
    print(stash.x)

def f2():
    stash.y = 2
    print(stash.y)

    try:
        stash.x
    except AttributeError:
        print("x is not local to f2")

g1 = gevent.spawn(f1)
g2 = gevent.spawn(f2)

gevent.joinall([g1, g2])
]]]
[[[end]]]

Molti framework web che usano gevent salvano gli oggetti delle sessioni HTTP all'interno di un gevent local thread. Per esempio, utilizzando la libreria Werkzeug ed il suo   Proxy possiamo creare degli oggetti request in stile Flask.

<pre>
<code class="python">from gevent.local import local
from werkzeug.local import LocalProxy
from werkzeug.wrappers import Request
from contextlib import contextmanager

from gevent.wsgi import WSGIServer

_requests = local()
request = LocalProxy(lambda: _requests.request)

@contextmanager
def sessionmanager(environ):
    _requests.request = Request(environ)
    yield
    _requests.request = None

def logic():
    return "Hello " + request.remote_addr

def application(environ, start_response):
    status = '200 OK'

    with sessionmanager(environ):
        body = logic()

    headers = [
        ('Content-Type', 'text/html')
    ]

    start_response(status, headers)
    return [body]

WSGIServer(('', 8000), application).serve_forever()


<code>
</pre>

Il sistema di Flask e' un po' piu' sofisticato di questo esempio, ma l'idea di utilizzare local thread e local session e' esattamente la stessa.

## Subprocess

A partire da gevent 1.0, ``gevent.subprocess`` -- una versione modificata del modulo Python
``subprocess`` -- e' stata aggiunta. Supporta waiting cooperativo su subrocess.

<pre>
<code class="python">
import gevent
from gevent.subprocess import Popen, PIPE

def cron():
    while True:
        print("cron")
        gevent.sleep(0.2)

g = gevent.spawn(cron)
sub = Popen(['sleep 1; uname'], stdout=PIPE, shell=True)
out, err = sub.communicate()
g.kill()
print(out.rstrip())
</pre>

<pre>
<code class="python">
cron
cron
cron
cron
cron
Linux
<code>
</pre>

Spesso si vuole utilizzare ``gevent`` e ``multiprocessing`` assieme. Una delle sfide piu' ovvie e' che la comicazione inter-processo fornita da ``multiprocessing`` non e' cooperativa di default. Siccome gli oggetti basati su ``multiprocessing.Connection`` (come ``Pipe``) espongono i propri file descriptor sottostanti, ``gevent.socket.wait_read`` e ``wait_write`` possono essere utilizzati per aspettare in maniera cooperativa degli eventi pronto-per-leggere/pronto-per-scrivere prima di iniziare a leggere o scrivere:

<pre>
<code class="python">
import gevent
from multiprocessing import Process, Pipe
from gevent.socket import wait_read, wait_write

# To Process
a, b = Pipe()

# From Process
c, d = Pipe()

def relay():
    for i in xrange(10):
        msg = b.recv()
        c.send(msg + " in " + str(i))

def put_msg():
    for i in xrange(10):
        wait_write(a.fileno())
        a.send('hi')

def get_msg():
    for i in xrange(10):
        wait_read(d.fileno())
        print(d.recv())

if __name__ == '__main__':
    proc = Process(target=relay)
    proc.start()

    g1 = gevent.spawn(get_msg)
    g2 = gevent.spawn(put_msg)
    gevent.joinall([g1, g2], timeout=1)
</code>
</pre>

Nota, comunque, la combinazione di ``multiprocessing`` e gevent puo' nascondere alcune insidie dipendenti dal sistema operativo, sopratutto:

* Dopo il [forking](http://linux.die.net/man/2/fork) su sistemi POSIX lo stato di gevent nel processo figlio e' mal posto. Un problema e' che le greenlet lanciate prima della creazione di ``multiprocessing.Process`` girano sia nel processo padre che nel processo figlio.

* ``a.send()`` in ``put_msg()`` menzionate sopra possono bloccare il thread chiamante in maniera non cooperativa: un evento pronto-a-scrivere assicura solo che un byte puo' essere scritto. Il buffer sottostante puo' essere pieno prima che il tentativo di scrittura sia finito.

* L'approccio basato su ``wait_write()`` / ``wait_read()`` non funziona su Windows (``IOError: 3 is not a socket (files are not supported)``), perche' Windows non puo' controllare gli eventi sulle pipe.

Il package Python [gipc](http://pypi.python.org/pypi/gipc) risolve questi problemi in modo per lo piu' trasparente sia su sistemi POSIX che Windows. Fornisce dei processi figli basati su ``multiprocessing.Process``, compatibili con gevent e comunicazione inter-processo basata su pipe.

## Attori

Il modello degli attori e' un modello di alto livello reso famoso dal linguaggio Erlang. In breve l'idea principale e' che c'e' una collezione di attori indipendenti che hanno una casella in cui ricevono i messaggi dagli altri attori. Il ciclo principale all'interno dell'attore scorre all'interno dei messaggi e compie azioni secondo il comportamento desiderato.

Gevent non ha un tipo nativo che definisce un attore, ma lo si puo' definire molto semplicemente utilizzando una Coda all'interno di una classe derivata da Greenlet.

<pre>
<code class="python">import gevent
from gevent.queue import Queue


class Actor(gevent.Greenlet):

    def __init__(self):
        self.inbox = Queue()
        Greenlet.__init__(self)

    def receive(self, message):
        """
        Define in your subclass.
        """
        raise NotImplemented()

    def _run(self):
        self.running = True

        while self.running:
            message = self.inbox.get()
            self.receive(message)

</code>
</pre>

Un caso di utilizzo:

<pre>
<code class="python">import gevent
from gevent.queue import Queue
from gevent import Greenlet

class Pinger(Actor):
    def receive(self, message):
        print(message)
        pong.inbox.put('ping')
        gevent.sleep(0)

class Ponger(Actor):
    def receive(self, message):
        print(message)
        ping.inbox.put('pong')
        gevent.sleep(0)

ping = Pinger()
pong = Ponger()

ping.start()
pong.start()

ping.inbox.put('start')
gevent.joinall([ping, pong])
</code>
</pre>

# Applicazioni nel mondo reale

## Gevent ZeroMQ

[ZeroMQ](http://www.zeromq.org/) e' descritto dai suoi autori come "una libreria socket che si comporta come un framework concorrente". E' un layer di comunicazione molto potente per la creazione di applicazioni distribuite.

ZeroMQ fornisce una varieta' di primitive socket, la piu' semplice crea una coppia di socket Richiesta-Risposta. Un socket ha due metodi importanti ``send`` e ``recv``, entrambi sono normalmente delle operazioni bloccanti. Questo viene risolto brillantemente dalla libreria di [Travis Cline](https://github.com/traviscline) che usa gevent.socket per interrogare dei socket ZeroMQ in modo non bloccante. Puoi installare gevent-zeromq tramite PyPi con il comando: ``pip install gevent-zeromq``

[[[cog
# Nota: Ricordati ``pip install pyzmq gevent_zeromq``
import gevent
from gevent_zeromq import zmq

# Global Context
context = zmq.Context()

def server():
    server_socket = context.socket(zmq.REQ)
    server_socket.bind("tcp://127.0.0.1:5000")

    for request in range(1,10):
        server_socket.send("Hello")
        print('Switched to Server for %s' % request)
        # Implicit context switch occurs here
        server_socket.recv()

def client():
    client_socket = context.socket(zmq.REP)
    client_socket.connect("tcp://127.0.0.1:5000")

    for request in range(1,10):

        client_socket.recv()
        print('Switched to Client for %s' % request)
        # Implicit context switch occurs here
        client_socket.send("World")

publisher = gevent.spawn(server)
client    = gevent.spawn(client)

gevent.joinall([publisher, client])

]]]
[[[end]]]

## Semplici Server

<pre>
<code class="python">
# On Unix: Access with ``$ nc 127.0.0.1 5000``
# On Window: Access with ``$ telnet 127.0.0.1 5000``

from gevent.server import StreamServer

def handle(socket, address):
    socket.send("Hello from a telnet!\n")
    for i in range(5):
        socket.send(str(i) + '\n')
    socket.close()

server = StreamServer(('127.0.0.1', 5000), handle)
server.serve_forever()
</code>
</pre>

## Server WSGI

Gevent fornisce due WSGI server per fornire contenuti su HTTP..
Sono chiamati ``wsgi`` and ``pywsgi``:

* gevent.wsgi.WSGIServer
* gevent.pywsgi.WSGIServer

Nelle versioni di gevent prima della 1.0.x, gevente usava libevent invece di libev. Libevent includeva un server HTTP performante che veniva utilizzato dal server ``wsgi``  di gevent.

In gevent 1.0.x non c'e' un server http incluso. Invece ``gevent.wsgi`` e' ora un alias del server ``gevent.pywsgi``.

## Streaming Servers

**se stai usando gevent 1.0.x, questa sezione non e' valida**

Per quelli che hanno familiarita' con servizi di streaming HTTP, l'idea principale e' che negli header non viene specificata la dimensione del body. Viene mantenuta invece la connessione aperta e vengono inviati blocchi di dati nella connessione, facendoli seguire ad un prefisso esadecimale che che indica la lunghezza del blocco. Lo stream e' chiuso quando un blocco di dimensione zero viene inviato.

    HTTP/1.1 200 OK
    Content-Type: text/plain
    Transfer-Encoding: chunked

    8
    <p>Hello

    9
    World</p>

    0

La connessione HTTP qui sopra non puo' essere creato in un server wsgi perche' lo streaming non e' supportato. Deve invece essere bufferizzato.

<pre>
<code class="python">from gevent.wsgi import WSGIServer

def application(environ, start_response):
    status = '200 OK'
    body = '&lt;p&gt;Hello World&lt;/p&gt;'

    headers = [
        ('Content-Type', 'text/html')
    ]

    start_response(status, headers)
    return [body]

WSGIServer(('', 8000), application).serve_forever()

</code>
</pre>

Using pywsgi we can however write our handler as a generator and
yield the result chunk by chunk.

<pre>
<code class="python">from gevent.pywsgi import WSGIServer

def application(environ, start_response):
    status = '200 OK'

    headers = [
        ('Content-Type', 'text/html')
    ]

    start_response(status, headers)
    yield "&lt;p&gt;Hello"
    yield "World&lt;/p&gt;"

WSGIServer(('', 8000), application).serve_forever()

</code>
</pre>

Tuttavia le performance di un server con Gevent sono di gran lunga maggiori di altri server implementati in Python. libev e' una tecnologia molto curata e i server da lei derivati sono noti per le performance e la scalabilita'.

Per verificarlo e' possibile utilizzare Apache Benchmark ``ab`` o vedere questo [Benchmark of Python WSGI Servers](http://nichol.as/benchmark-of-python-web-servers) per fare una comparazione con gli altri server.

<pre>
<code class="shell">$ ab -n 10000 -c 100 http://127.0.0.1:8000/
</code>
</pre>

## Long Polling

<pre>
<code class="python">import gevent
from gevent.queue import Queue, Empty
from gevent.pywsgi import WSGIServer
import simplejson as json

data_source = Queue()

def producer():
    while True:
        data_source.put_nowait('Hello World')
        gevent.sleep(1)

def ajax_endpoint(environ, start_response):
    status = '200 OK'
    headers = [
        ('Content-Type', 'application/json')
    ]

    start_response(status, headers)

    while True:
        try:
            datum = data_source.get(timeout=5)
            yield json.dumps(datum) + '\n'
        except Empty:
            pass


gevent.spawn(producer)

WSGIServer(('', 8000), ajax_endpoint).serve_forever()

</code>
</pre>

## Websockets

Esempio di websocket che richiede <a href="https://bitbucket.org/Jeffrey/gevent-websocket/src">gevent-websocket</a>.


<pre>
<code class="python"># Simple gevent-websocket server
import json
import random

from gevent import pywsgi, sleep
from geventwebsocket.handler import WebSocketHandler

class WebSocketApp(object):
    '''Send random data to the websocket'''

    def __call__(self, environ, start_response):
        ws = environ['wsgi.websocket']
        x = 0
        while True:
            data = json.dumps({'x': x, 'y': random.randint(1, 5)})
            ws.send(data)
            x += 1
            sleep(0.5)

server = pywsgi.WSGIServer(("", 10000), WebSocketApp(),
    handler_class=WebSocketHandler)
server.serve_forever()
</code>
</pre>

HTML Page:

    <html>
        <head>
            <title>Minimal websocket application</title>
            <script type="text/javascript" src="jquery.min.js"></script>
            <script type="text/javascript">
            $(function() {
                // Open up a connection to our server
                var ws = new WebSocket("ws://localhost:10000/");

                // What do we do when we get a message?
                ws.onmessage = function(evt) {
                    $("#placeholder").append('<p>' + evt.data + '</p>')
                }
                // Just update our conn_status field with the connection status
                ws.onopen = function(evt) {
                    $('#conn_status').html('<b>Connected</b>');
                }
                ws.onerror = function(evt) {
                    $('#conn_status').html('<b>Error</b>');
                }
                ws.onclose = function(evt) {
                    $('#conn_status').html('<b>Closed</b>');
                }
            });
        </script>
        </head>
        <body>
            <h1>WebSocket Example</h1>
            <div id="conn_status">Not Connected</div>
            <div id="placeholder" style="width:600px;height:300px;"></div>
        </body>
    </html>


## Chat Server

Il motivante esempio finale, una chatroom in realtime. Questo esempio richiede <a href="http://flask.pocoo.org/">Flask</a> (ma non necessariamente, puo' funzionare anche con Django, Pyramid, ecc..). I corrispondenti file Javascript e HTML possono essere trovati <a href="https://github.com/sdiehl/minichat">qui</a>.

<pre>
<code class="python"># Micro gevent chatroom.
# ----------------------

from flask import Flask, render_template, request

from gevent import queue
from gevent.pywsgi import WSGIServer

import simplejson as json

app = Flask(__name__)
app.debug = True

rooms = {
    'topic1': Room(),
    'topic2': Room(),
}

users = {}

class Room(object):

    def __init__(self):
        self.users = set()
        self.messages = []

    def backlog(self, size=25):
        return self.messages[-size:]

    def subscribe(self, user):
        self.users.add(user)

    def add(self, message):
        for user in self.users:
            print(user)
            user.queue.put_nowait(message)
        self.messages.append(message)

class User(object):

    def __init__(self):
        self.queue = queue.Queue()

@app.route('/')
def choose_name():
    return render_template('choose.html')

@app.route('/&lt;uid&gt;')
def main(uid):
    return render_template('main.html',
        uid=uid,
        rooms=rooms.keys()
    )

@app.route('/&lt;room&gt;/&lt;uid&gt;')
def join(room, uid):
    user = users.get(uid, None)

    if not user:
        users[uid] = user = User()

    active_room = rooms[room]
    active_room.subscribe(user)
    print('subscribe %s %s' % (active_room, user))

    messages = active_room.backlog()

    return render_template('room.html',
        room=room, uid=uid, messages=messages)

@app.route("/put/&lt;room&gt;/&lt;uid&gt;", methods=["POST"])
def put(room, uid):
    user = users[uid]
    room = rooms[room]

    message = request.form['message']
    room.add(':'.join([uid, message]))

    return ''

@app.route("/poll/&lt;uid&gt;", methods=["POST"])
def poll(uid):
    try:
        msg = users[uid].queue.get(timeout=10)
    except queue.Empty:
        msg = []
    return json.dumps(msg)

if __name__ == "__main__":
    http = WSGIServer(('', 5000), app)
    http.serve_forever()
</code>
</pre>
