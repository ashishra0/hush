import { Bar, Collapse, Stage, Text, Window, type Act } from '../../kit'
import './hush.css'

// Hush: ⌘⇧Space over another app, type, ↵ saves to Inbox as a pill.
// ⌘O opens the outline with the new task selected, ⌘↵ strikes and folds it,
// ⌘W closes the outline and we are back where we started (the loop).

type S = {
  capture: boolean
  typed: string
  saved: boolean // panel has morphed into the pill
  pill: boolean // pill visible
  outline: boolean
  done: boolean // strike + fill
  folded: boolean
  toast: boolean
}

const initial: S = { capture: false, typed: '', saved: false, pill: false, outline: false, done: false, folded: false, toast: false }
const TASK = 'Book flights for the offsite'
const POSTER: S = { ...initial, outline: true }

async function script(a: Act<S>) {
  await a.wait(700)
  a.mark('summon')
  await a.key('cmd+shift+space')
  await a.set({ capture: true })
  await a.wait(500)
  a.mark('type')
  await a.type('typed', TASK, { interval: 55 })
  await a.wait(500)
  a.mark('save')
  await a.key('enter')
  await a.set({ saved: true, pill: true })
  await a.wait(1200)
  await a.set({ pill: false })
  await a.wait(200)
  await a.snap({ capture: false, saved: false, typed: '' })
  a.mark('open')
  await a.key('cmd+o')
  await a.set({ outline: true })
  await a.wait(1600)
  a.mark('complete')
  await a.key('cmd+enter')
  await a.set({ done: true })
  await a.wait(320)
  await a.set({ folded: true, toast: true })
  await a.wait(2200)
  a.mark('close')
  await a.key('cmd+w')
  await a.set({ outline: false, toast: false })
  await a.wait(350)
  await a.snap({ done: false, folded: false })
}

function Keycap({ k }: { k: string }) {
  return <span className="hu-kc">{k}</span>
}

function Circle({ on }: { on?: boolean }) {
  return <span className="hu-circle" data-on={on || undefined} />
}

function Folder() {
  return (
    <svg className="hu-folder" width="14" height="14" viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.3">
      <path d="M1.75 4.25v8a1 1 0 0 0 1 1h10.5a1 1 0 0 0 1-1v-6.5a1 1 0 0 0-1-1H8L6.5 3.25H2.75a1 1 0 0 0-1 1Z" strokeLinejoin="round" />
    </svg>
  )
}

function Chevron() {
  return (
    <svg className="hu-chev" width="10" height="10" viewBox="0 0 10 10" fill="none" stroke="currentColor" strokeWidth="1.5">
      <path d="M2.5 3.75 5 6.25l2.5-2.5" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  )
}

function Capture({ s }: { s: S }) {
  return (
    <div className="hu-capture" data-show={s.capture || undefined} data-saved={s.saved || undefined} data-gone={(s.saved && !s.pill) || undefined}>
      <div className="hu-panel">
        <div className="hu-input">
          {s.typed ? <span className="hu-typed">{s.typed}</span> : <span className="hu-ph">What's on your mind?</span>}
          <span key={s.typed.length} className="hu-caret" />
        </div>
        <div className="hu-foot">
          <span className="hu-dest"><Folder /><Text>Inbox</Text></span>
          <span className="hu-hints">
            <span className="hu-hint"><Keycap k="⇥" /><Text>Details</Text></span>
            <span className="hu-hint hu-strong"><Keycap k="↵" /><Text>Save</Text></span>
          </span>
        </div>
      </div>
      <div className="hu-pill">
        <span className="hu-check">
          <svg width="10" height="10" viewBox="0 0 10 10" fill="none" stroke="white" strokeWidth="1.8"><path d="m2.25 5.25 1.75 1.75 3.75-4" strokeLinecap="round" strokeLinejoin="round" /></svg>
        </span>
        <Text>Saved to <b>Inbox</b></Text>
      </div>
    </div>
  )
}

function Outline({ s }: { s: S }) {
  return (
    <div className="hu-outline" data-show={s.outline || undefined}>
      <Window title="Home" className="hu-win" toolbar={<span className="hu-find"><Text>Find</Text><span className="hu-find-k">⌘F</span></span>}>
        <div className="hu-page">
          <div className="hu-head">
            <div className="hu-title">Home</div>
            <Text className="hu-meta">8 open</Text>
          </div>
          <div className="hu-rows">
            <div className="hu-row">
              <Chevron />
              <Folder />
              <Text className="hu-t">Inbox</Text>
            </div>
            <div className="hu-kids">
              <Collapse open={!s.folded}>
                <div className="hu-row hu-sel" data-done={s.done || undefined}>
                  <span className="hu-gap" />
                  <Circle on={s.done} />
                  <span className="hu-strikewrap"><Text className="hu-t">{TASK}</Text><span className="hu-strike" /></span>
                </div>
              </Collapse>
              <div className="hu-row" data-next={s.folded || undefined}>
                <span className="hu-gap" />
                <Circle />
                <Text className="hu-t">Renew passport</Text>
              </div>
            </div>
            <div className="hu-row">
              <Chevron />
              <Circle />
              <Text className="hu-t">Work</Text>
            </div>
            <div className="hu-kids">
              {[132, 196, 104].map((w, i) => (
                <div key={i} className="hu-row">
                  <span className="hu-gap" />
                  <Circle />
                  <Bar w={w} h={7} tone={3} />
                </div>
              ))}
            </div>
          </div>
        </div>
        <div className="hu-toast" data-show={s.toast || undefined}>
          <Text>Done · {TASK}</Text>
          <span className="hu-toast-k">⌘Z Undo</span>
        </div>
      </Window>
    </div>
  )
}

export default function HushDemo() {
  return (
    <Stage width={760} height={460} initial={initial} poster={POSTER} script={script} keys="bottom-right" className="hu-stage">
      {(s) => (
        <div className="hu-desk">
          <div className="hu-menubar">
            <span className="hu-mb-left">
              <Bar w={30} h={7} tone={5} />
              <Bar w={22} h={6} tone={3} />
              <Bar w={26} h={6} tone={3} />
              <Bar w={30} h={6} tone={3} />
            </span>
            <span className="hu-mb-right">
              <span className="hu-mbicon" data-on={s.capture || undefined} />
              <Bar w={14} h={9} r={3} tone={3} />
              <Bar w={14} h={9} r={3} tone={3} />
              <Bar w={56} h={6} tone={4} />
            </span>
          </div>
          <div className="hu-other" data-receded={s.outline || undefined}>
            <Window title="" className="hu-otherwin">
              <div className="hu-doc">
                <Bar w={220} h={10} tone={4} />
                {[440, 400, 460, 320, 0, 430, 380, 410, 280].map((w, i) => (w ? <Bar key={i} w={w} h={6} tone={2} /> : <span key={i} className="hu-sp" />))}
              </div>
            </Window>
          </div>
          <Outline s={s} />
          <Capture s={s} />
        </div>
      )}
    </Stage>
  )
}
