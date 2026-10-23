"""Failure controls for saved-original campaign checkpoints (no game assets)."""
import json
import contextlib
import io
from pathlib import Path
from tempfile import TemporaryDirectory
from types import SimpleNamespace
import unittest
from unittest.mock import patch
import checkpoints as c


class CheckpointsTest(unittest.TestCase):
    def test_zero_is_absent_only_for_campaign_vars(self):
        self.assertEqual(c.diff({'gate': 0}, {}), [])
        self.assertEqual(c.observation_diff({'item101': 0}, {}), ['missing observation item101'])
        self.assertTrue(c.observation_diff({'money': 100}, {'money': 99}))

    def test_nonfinite_value_cannot_pass(self):
        for v in (float('nan'), float('inf'), -float('inf')):
            self.assertTrue(c.diff({'objective': 2}, {'objective': v}))
            with self.assertRaises(ValueError):
                c.validate_checkpoint(self.cp(vars_after={'objective': v}))

    def test_parser_retains_quoted_console_arguments(self):
        self.assertEqual(c.parse_step('script GiveQuestItem(0, "Kel1")'),
                         {'script': 'GiveQuestItem(0, "Kel1")'})
        self.assertEqual(c.parse_step('leave 2 gz1h'), {'leave': '2', 'destination': 'gz1h'})
        self.assertEqual(c.parse_step('leave 1 gz33j 3'),
                         {'leave': '1', 'destination': 'gz33j', 'entrance': '3'})
        self.assertEqual(c.parse_step('reload'), {'reload': True})
        with self.assertRaises(SystemExit): c.parse_step('use')

    def test_map_arrival_validation_does_not_allow_unrecognized_step_fields(self):
        c.validate_checkpoint(self.cp(steps=[{'leave': 1, 'destination': 'gz33j', 'entrance': 3}]))
        for value in (0, -1, 1.5, float('nan'), True, 'three'):
            with self.assertRaisesRegex(ValueError, 'positive integer'):
                c.validate_checkpoint(self.cp(steps=[{'leave': 1, 'destination': 'gz33j', 'entrance': value}]))
        for step in ({'use': 1, 'entrance': 3}, {'leave': 1, 'destination': 'gz33j', 'arrival': 3}):
            with self.assertRaisesRegex(ValueError, 'unexpected step fields'):
                c.validate_checkpoint(self.cp(steps=[step]))

    def test_unknown_and_invalid_entry_rejected(self):
        for steps in ([{'telepathy': 42}], [{'enter': 'gz1d1'}],
                      [{'wait': 1}, {'enter': 'bz1h'}], [{'wait': -1}], [{'wait': float('nan')}]):
            with self.assertRaises(ValueError): c.validate_checkpoint(self.cp(steps=steps))

    def test_new_reference_must_name_actual_executable(self):
        with self.assertRaises(ValueError): c.validate_checkpoint(self.cp(schema=2))

    def test_probe_cannot_replace_mandatory_money_observation(self):
        for name in ('money', 'Money', 'MONEY'):
            with self.assertRaisesRegex(ValueError, 'reserved observation'):
                c.validate_checkpoint(self.cp(probes={name: 'GSGetVar(0,"dummy")'}))
        c.validate_checkpoint(self.cp(probes={'cp_money': 'GetMoney(0)'}))

    def test_only_declared_capture_nonce_is_removed_when_recording(self):
        with TemporaryDirectory() as d:
            root = Path(d)
            source = root / 'source.exe'
            source.write_bytes(b'local recording control')
            before, after = root / 'before', root / 'after'
            for folder in (before, after):
                folder.mkdir()
                (folder / 'mission.sav').write_bytes(folder.name.encode())
            def read_slot(path, decoder):
                n = 1 if path == before else 2
                return {'zone': 'bz1h', 'live': {'money': 100, 'vars': {
                    'cp_capture_nonce': n, 'cp_other': n, 'q.real_objective': n, 'gtime': n}}}
            fake_reader = SimpleNamespace(Decoder=lambda path: None, read_slot=read_slot)
            args = SimpleNamespace(game_exe=source, source_exe=source, before=before, after=after,
                step=['wait 0'], campaign='lost_in_astral', note=None, fixture=None, probes=None,
                settle=None, after_settle=None, script_transition=False, name='capture_control',
                recording_only_var=['cp_capture_nonce'])
            with patch.dict('sys.modules', {'original_save': fake_reader}), \
                    patch.object(c, 'STORE', root / 'checkpoints'), patch.object(c, 'REPO', root), \
                    contextlib.redirect_stdout(io.StringIO()):
                c.make(args)
                recorded = json.loads((c.STORE / 'capture_control.json').read_text())
                self.assertEqual(recorded['vars_before'], {'cp_other': 1, 'q.real_objective': 1})
                self.assertEqual(recorded['vars_after'], {'cp_other': 2, 'q.real_objective': 2})
                self.assertEqual(recorded['provenance']['recording_only_vars'], ['cp_capture_nonce'])
                self.assertTrue(recorded['provenance']['before']['mission.sav'])
                args.recording_only_var = ['q.real_objective']
                with self.assertRaisesRegex(ValueError, 'only cp_capture_nonce'):
                    c.make(args)

    def test_nonce_metadata_cannot_hide_arbitrary_game_or_probe_values(self):
        for names in (['cp_other'], ['q.real_objective'], 'cp_capture_nonce', [{}]):
            with self.assertRaises(ValueError):
                c.validate_checkpoint(self.cp(provenance={'recording_only_vars': names}))
        with self.assertRaises(ValueError):
            c.validate_checkpoint(self.cp(provenance={'recording_only_vars': ['cp_capture_nonce']},
                probes={'cp_capture_nonce': 'GetMoney(0)'}))

    def test_output_inside_source_is_rejected_before_creation_or_copy(self):
        with TemporaryDirectory() as d:
            root = Path(d)
            source = root / 'game'
            source.mkdir()
            alias = root / 'source-alias'
            alias.symlink_to(source, target_is_directory=True)
            selection = root / 'selection.json'
            selection.write_text(json.dumps({'control': self.cp()}))
            for output in (source / 'results', alias / 'results'):
                args = SimpleNamespace(replay_selection=selection, name=None, godot='fake-godot',
                    repeat=1, work_dir=output, game_source=source)
                with patch('run.stage_game') as stage:
                    with self.assertRaisesRegex(ValueError, 'outside the game'):
                        c.run(args)
                    stage.assert_not_called()
                self.assertFalse(output.exists())
            with self.assertRaises(ValueError): c.validate_work_dir(source, source)
            with self.assertRaises(ValueError): c.validate_work_dir(source, c.REPO / 'tools/tests/results')
            c.validate_work_dir(source, root / 'safe-output')

    def test_reproduction_preserves_resolved_inputs_and_extended_timeout(self):
        args = SimpleNamespace(godot='/tools/godot', game_source=Path('relative project/game'),
            repeat=3, timeout=777, game_dir=Path('owned base'), astral_dir=Path('owned LiA'))
        work = Path('saved evidence')
        argv = c.reproduction_argv(args, work, ['first', 'second'])
        for flag, value in (
                ('--game-source', str(args.game_source.resolve())),
                ('--game-dir', str(args.game_dir.resolve())),
                ('--astral-dir', str(args.astral_dir.resolve())),
                ('--replay-selection', str(work.resolve() / 'selection.json')),
                ('--repeat', '3'), ('--timeout', '777')):
            self.assertEqual(argv[argv.index(flag)+1], value)
        self.assertEqual([argv[i+1] for i, item in enumerate(argv) if item == '--name'],
                         ['first', 'second'])

    def cp(self, **updates):
        return dict({'campaign': 'lost_in_astral', 'zone': 'bz1h', 'steps': [{'wait': 1}],
                     'vars_before': {}, 'vars_after': {'quest': 2}}, **updates)

    def capture(self, text, code=0, cp=None):
        with TemporaryDirectory() as d:
            args = SimpleNamespace(astral_dir=Path(d), game_dir=None,
                runtime=Path(d), godot='fake-godot', timeout=1)
            def process(argv, log, env, timeout):
                log.write_text(text)
                return code, None
            with patch.object(c, 'capture_process', process):
                return c.run_one('fixture', self.cp() if cp is None else cp, args, Path(d)/'out')

    def result(self, **updates):
        row = dict({'entry': {}, 'after': {'quest': 2}, 'zone': 'bz1h',
                    'checks': 1, 'failures': 0}, **updates)
        return 'CHECKPOINT_RESULT ' + json.dumps(row) + '\n'

    def test_nominal_success_requires_one_clean_complete_result(self):
        self.assertTrue(self.capture(self.result())['ok'])
        for text in ('', self.result()*2, 'ERROR: failed\n'+self.result(),
                     'SCRIPT ERROR: broken\n'+self.result()):
            self.assertIn('error', self.capture(text))
        self.assertIn('error', self.capture(self.result(), 7))
        self.assertFalse(self.capture(self.result(), 1)['ok'])
        self.assertFalse(self.capture(self.result(checks=0))['ok'])

    def test_real_failures_and_wrong_destination_remain_red(self):
        self.assertFalse(self.capture(self.result(failures=1))['ok'])
        self.assertTrue(self.capture(self.result(after={'quest': 1}))['delta'])
        self.assertTrue(self.capture(self.result(zone='gz1d1'))['destination'])

    def test_expected_results_are_not_staged_in_remake_input(self):
        cp = self.cp(observations_after={'money': 42}, expected_zone='gz1d1')
        with TemporaryDirectory() as d:
            args = SimpleNamespace(astral_dir=Path(d), game_dir=None,
                runtime=Path(d), godot='fake-godot', timeout=1)
            def process(argv, log, env, timeout):
                payload = Path(next(arg.split('=', 1)[1] for arg in argv if arg.startswith('--checkpoint=')))
                staged = json.loads(payload.read_text())
                self.assertEqual(set(staged), {'zone', 'campaign', 'vars_before', 'settle',
                    'after_settle', 'fixture', 'probes', 'steps'})
                self.assertEqual(staged['vars_before'], cp['vars_before'])
                log.write_text(self.result(zone='gz1d1', observations_after={'money': 42}))
                return 0, None
            with patch.object(c, 'capture_process', process):
                self.assertTrue(c.run_one('boundary', cp, args, Path(d)/'out')['ok'])

    def test_required_clear_cannot_be_mistaken_for_unchanged_missing_delta(self):
        # GS stores omit zeros, but the *change set* must contain the clear.
        self.assertTrue(c.observation_diff({'rescue_gate': 0}, {}))
        self.assertEqual(c.observation_diff({'rescue_gate': 0}, {'rescue_gate': 0}), [])
        cp = self.cp(vars_before={'rescue_gate': 1}, vars_after={})
        report = self.capture(self.result(entry={'rescue_gate': 1}, after={'rescue_gate': 1}), cp=cp)
        self.assertFalse(report['ok'])
        self.assertEqual(report['delta'], ['missing observation rescue_gate'])

    def test_clock_exclusion_does_not_hide_exit_or_objective(self):
        self.assertEqual(c.kept({'gtime': 7, 'zt.gz1h': 1, 'zs.gz1h': 1,
            'z.gz1h': 1, 'q.gz1h.fq2': 2}), {'z.gz1h': 1, 'q.gz1h.fq2': 2})


if __name__ == '__main__': unittest.main()
