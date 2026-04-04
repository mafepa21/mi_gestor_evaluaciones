import 'package:flutter/material.dart';

class SectionCard extends StatelessWidget {
  const SectionCard({
    required this.title,
    required this.child,
    this.subtitle,
    this.actions = const <Widget>[],
    this.expandChild = false,
    super.key,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final List<Widget> actions;
  final bool expandChild;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final content = Padding(
            padding: const EdgeInsets.all(20),
            child: _SectionCardContent(
              title: title,
              subtitle: subtitle,
              actions: actions,
              expandChild: expandChild,
              child: child,
            ),
          );

          if (!expandChild && constraints.hasBoundedHeight) {
            return SingleChildScrollView(child: content);
          }

          return content;
        },
      ),
    );
  }
}

class _SectionCardContent extends StatelessWidget {
  const _SectionCardContent({
    required this.title,
    required this.subtitle,
    required this.actions,
    required this.expandChild,
    required this.child,
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final bool expandChild;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle!,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ],
              ),
            ),
            if (actions.isNotEmpty) ...[
              const SizedBox(width: 12),
              Flexible(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.end,
                  children: actions,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 16),
        if (expandChild) Expanded(child: child) else child,
      ],
    );
  }
}
